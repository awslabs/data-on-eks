from typing import Any, Optional

import numpy as np
import torch
import torch.distributed as dist
import torch_xla.core.xla_model as xm
from modeling_llama_nxd import LlamaForCausalLM
from training_utils import Throughput, get_sin_cos_matrix
from transformers import GenerationConfig

import neuronx_distributed as nxd
from neuronx_distributed.lightning import NeuronLTModule
from neuronx_distributed.parallel_layers import parallel_state
from neuronx_distributed.trainer import (
    initialize_parallel_model,
    initialize_parallel_optimizer,
)


class NeuronLlamaLTModule(NeuronLTModule):
    def __init__(self, tokenizer=None, use_deferred_init=False, *args: Any, **kwargs: Any):
        super().__init__(*args, **kwargs)
        self.tokenizer = tokenizer  # tokenizer is added here
        self.validation_step_outputs = []
        self.use_deferred_init = use_deferred_init

    def setup(self, stage=None):
        def get_model(model_config):
            # For delayed parameter inititalization
            # Check https://pytorch.org/torchdistx/latest/deferred_init.html
            try:
                from torchdistx import deferred_init
            except ImportError:
                deferred_init = None
            if self.use_deferred_init > 0 and deferred_init is not None:
                model = deferred_init.deferred_init(LlamaForCausalLM, model_config)
            else:
                model = LlamaForCausalLM(model_config)
            # Here we make sure we use the same sine and cosine matrices for all layers.
            # Making use of same tensors would make the CSE algorithm eliminate the lookup call
            # from layers, keeping only lookup from first layer.
            with torch.no_grad():
                cos, sin = get_sin_cos_matrix(model_config)
                for layer in model.model.layers:
                    layer.self_attn.rotary_emb.cos_cached = cos
                    layer.self_attn.rotary_emb.sin_cached = sin
            num_params = sum([np.prod(p.size()) for p in model.parameters()])
            if dist.get_rank() == 0:
                print(f"# total parameters: {num_params}")
                print(f"model config {model_config}")
            return model

        self.model = initialize_parallel_model(
            self.nxd_config,
            get_model,
            *self.model_args,
            **self.model_kwargs,
        )
        self.averaged_loss = torch.zeros(1, dtype=torch.double).to(xm.xla_device())
        self.print_pp_rank = 0 if self.log_rank0 else self.trainer.strategy.pipeline_parallel_size - 1
        # Make the model Neuron-compatible for generation
        try:
            from optimum.neuron.utils.training_utils import (
                patch_generation_mixin_to_general_neuron_generation_mixin,
            )

            patch_generation_mixin_to_general_neuron_generation_mixin(self.model.module)
        except ImportError:
            print("Failed to import optimum-neuron dependency, generation will not work on Neuron.")
        # Load Pretrained checkpoint
        if hasattr(self.model_args[0], "pretrained_ckpt") and self.model_args[0].pretrained_ckpt:
            user_content = nxd.load_checkpoint(
                self.model_args[0].pretrained_ckpt,
                tag="pretrained_weight",
                model=self.model,
                optimizer=None,
                scheduler=None,
                strict=False,
            )

    def training_step(self, batch, batch_idx):
        xm.mark_step()

        for logger in self.trainer.loggers:
            logger.print_step = -1
        self.should_print = False
        if self.trainer.strategy.pipeline_parallel_size > 1:
            loss = self.model.run_train(
                input_ids=batch["input_ids"],
                attention_mask=batch["attention_mask"],
                labels=batch["labels"],
            )

            loss_detached = (
                loss.detach() if self.trainer.strategy.pipeline_parallel_rank == self.print_pp_rank else None
            )
        else:
            # print(f"self model is {self.model}")
            outputs = self.model(
                input_ids=batch["input_ids"],
                attention_mask=batch["attention_mask"],
                labels=batch["labels"],
            )
            # print(f"outputs is {outputs}")
            loss = outputs.loss / self.grad_accum_steps
            loss.backward()
            self.averaged_loss += loss.detach()
            xm.mark_step()
        if not self.automatic_optimization and (batch_idx + 1) % self.grad_accum_steps == 0:
            self.should_print = True
            if (
                self.trainer.strategy.pipeline_parallel_size == 1
            ):  # Todo: At this moment we only average loss among dp ranks in tp cases
                loss_div = self.averaged_loss / self.trainer.strategy.data_parallel_size
                loss_reduced = xm.all_reduce(
                    xm.REDUCE_SUM,
                    loss_div,
                    groups=parallel_state.get_data_parallel_group(as_list=True),
                )
                loss_detached = loss_reduced.detach()
                self.averaged_loss.zero_()

            optimizer = self.optimizers()
            scheduler = self.lr_schedulers()
            optimizer.step()
            self.global_norm = optimizer.grad_norm
            optimizer.zero_grad()
            scheduler.step()
            xm.mark_step()

            # Setup items for logging
            self.loss = loss_detached
            self.lr = self.lr_schedulers().get_lr()[0]
            self.input_ids = batch["input_ids"]
            self.tps = self.throughput.get_throughput()

        return loss

    def generate(
        self, input_ids: Optional[torch.Tensor] = None, generation_config: Optional[GenerationConfig] = None, **kwargs
    ):
        return self.model.module.generate(
            input_ids=input_ids,
            generation_config=generation_config,
            **kwargs,
        )

    def configure_optimizers(self):
        param_groups = self.get_param_groups_by_weight_decay()
        optimizer = initialize_parallel_optimizer(self.nxd_config, self.opt_cls, param_groups, **self.opt_kwargs)
        optimizer.zero_grad()

        scheduler = self.scheduler_cls(optimizer, *self.scheduler_args, **self.scheduler_kwargs)
        self.throughput = Throughput(
            self.train_batch_size,
            parallel_state.get_data_parallel_size(),
            self.grad_accum_steps,
            10,
            self.logging_interval,
        )
        return (
            [optimizer],
            [
                {
                    "scheduler": scheduler,
                }
            ],
        )

    def on_train_batch_end(self, *args, **kwargs):
        if (
            self.trainer.strategy.data_parallel_rank == 0
            and self.trainer.strategy.tensor_parallel_rank == 0
            and self.trainer.strategy.pipeline_parallel_rank == self.print_pp_rank
        ):
            if self.should_print:
                print(
                    f"step {self.global_step} loss is {self.loss.detach().cpu().item()}, lr is {self.lr}, throughput {self.tps} seq/s,  input_ids {torch.sum(self.input_ids.detach().cpu()).item()}, norm {self.global_norm}, global rank {xm.get_ordinal()}"
                )

        # # Logging, need to revisit when automatic_optimization enabled
        if not self.automatic_optimization:
            if self.should_print:
                self.log(
                    "loss",
                    self.loss.detach().cpu().item()
                    if self.loss is not None
                    else torch.zeros(1, device="cpu", requires_grad=False),
                    prog_bar=True,
                )
                self.log(
                    "lr",
                    self.lr,
                    prog_bar=True,
                )
                self.log(
                    "input_ids",
                    torch.sum(self.input_ids.detach().cpu()).item(),
                    prog_bar=True,
                )
                self.log("throughput", self.tps, prog_bar=True)
                self.log(
                    "global_step",
                    self.global_step,
                    prog_bar=True,
                    on_step=True,
                    on_epoch=True,
                )
                for logger in self.trainer.loggers:
                    logger.print_step = self.global_step

