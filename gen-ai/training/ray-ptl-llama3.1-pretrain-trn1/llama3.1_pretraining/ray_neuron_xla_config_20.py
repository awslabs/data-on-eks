from ray.train.torch.xla import TorchXLAConfig
from ray.train.torch.xla.config import _TorchAwsNeuronXLABackend # Accessing an internal class
from ray.train._internal.worker_group import WorkerGroup
import os
import ray
import torch

def _set_xla_env_vars():
    # https://pytorch.org/docs/1.13/elastic/run.html#environment-variables
    context = ray.train.get_context()

    local_world_size = context.get_local_world_size()

    env_variables = {
        "LOCAL_RANK": str(context.get_local_rank()),
        "RANK": str(context.get_world_rank()),
        "LOCAL_WORLD_SIZE": str(local_world_size),
        "WORLD_SIZE": str(context.get_world_size()),
        "GROUP_RANK": str(context.get_world_size()),
        "GROUP_WORLD_SIZE": str(context.get_world_size() / local_world_size),
        "ROLE_RANK": str(context.get_world_rank()),
        "ROLE_WORLD_RANK": str(context.get_world_rank()),
        "ROLE_WORLD_SIZE": str(context.get_world_size()),
    }

    for name, value in env_variables.items():
        # print (f"ray_neuron_xla_config_20: _set_xla_env_vars: Setting the variable {name} from {os.environ.get(name)} to {value}")
        os.environ[name] = value

    # EFA and XLA setup
    # https://github.com/aws/libfabric/blob/master/prov/efa/src/rxr/rxr_init.c
    # https://github.com/aws-neuron/aws-neuron-samples/blob/master/torch-neuronx/training/dp_bert_hf_pretrain/run_dp_bert_large_hf_pretrain_bf16_s128.sh # noqa
    os.environ["FI_PROVIDER"] = "efa"
    os.environ["FI_EFA_USE_DEVICE_RDMA"] = "1"
    os.environ["FI_EFA_FORK_SAFE"] = "1"
    os.environ["XLA_TRANSFER_SEED_ASYNC"] = "1"
    os.environ["NCCL_ASYNC_ERROR_HANDLING"] = "1"

def _set_pjrt_env_variables():
    '''
    # PK_Open_Q: Copied from src/KaenaXlaPyTorch/src/torch_neuronx/xla.py
    In torchrun scenearios, are the "LOCAL_*" env variables set even before torch_xla module is initialized (which calls the above torch_neuronx method)?
    Is that the core problem with enabling Ray which uses "python" directly to launch the training?
    Even in that case, why does this workaround of setting the PJRT environment variables right before we call dist.init_process_group work still causing pjrt client initialization issues?
    '''
    assert torch.__version__.startswith("2.")
    assert "WORLD_SIZE" in os.environ,  "WORLD_SIZE environment variable should have been set by now!"
    assert "LOCAL_WORLD_SIZE" in os.environ,  "LOCAL_WORLD_SIZE environment variable should have been set by now!"
    assert "LOCAL_RANK" in os.environ,  "LOCAL_RANK environment variable should have been set by now!"

    env_variables = {
        "NEURON_PJRT_PROCESS_INDEX": os.environ["RANK"],
        "PJRT_LOCAL_PROCESS_RANK":  os.environ["LOCAL_RANK"],
        "NEURON_RT_VISIBLE_CORES": os.environ["LOCAL_RANK"],
    }
    for name, value in env_variables.items():
        print (f"ray_neuron_xla_config_20: _set_pjrt_env_variables: Setting the variable {name} from {os.environ.get(name)} to {value}")
        os.environ[name] = value


def _setup_xla_torch_process_group():
    try:
        import torch.distributed as dist
        import torch_xla.core.xla_model as xm  # noqa F401

        if torch.__version__.startswith("2."):
            _set_pjrt_env_variables()

        # print (f"ray_neuron_xla_config_20: _setup_xla_torch_process_group: {os.environ.get('RANK')=}, {os.environ.get('PJRT_DEVICE')=}, {os.environ.get('LOCAL_WORLD_SIZE')=}, {os.environ.get('LOCAL_RANK')=}, {os.environ.get('NEURON_PJRT_PROCESSES_NUM_DEVICES')=}, {os.environ.get('PJRT_LOCAL_PROCESS_COUNT')=}, {os.environ.get('NEURON_RT_NUM_CORES')=}, {torch.__version__=}")
        # print (f"ray_neuron_xla_config_20: _setup_xla_torch_process_group: {os.environ.get('RANK')=}, {os.environ.get('LOCAL_RANK')=}, {os.environ.get('LOCAL_WORLD_SIZE')=}, {os.environ.get('NEURON_PJRT_PROCESSES_NUM_DEVICES')=}, {os.environ.get('PJRT_LOCAL_PROCESS_COUNT')=}, {os.environ.get('NEURON_RT_NUM_CORES')=}, {os.environ.get('NEURON_RT_VISIBLE_CORES')=}, {os.environ.get('NEURON_PJRT_WORLD_SIZE')=}, {os.environ.get('NEURON_PJRT_PROCESS_INDEX')=}")
        if torch.__version__.startswith("2.0"):
            import torch_xla.experimental.pjrt_backend  # noqa
            global_rank = int(os.environ.get("RANK")) # Is this needed at all?
            dist.init_process_group("xla", init_method="pjrt://") # Should we pass rank=global_rank ?? Why?
        else:
            import torch_xla.distributed.xla_backend  # noqa F401
            dist.init_process_group("xla")
    except ImportError:
        raise ImportError("torch_xla must be installed to use torch_xla backend.")


class NewTorchXLAConfig(TorchXLAConfig):
    @property
    def backend_cls(self):
        return _NewTorchAwsNeuronXLABackend
    
class _NewTorchAwsNeuronXLABackend(_TorchAwsNeuronXLABackend):
    def on_start(self, worker_group: WorkerGroup, backend_config: TorchXLAConfig):
        print (f"ray_neuron_xla_config_20: _NewTorchAwsNeuronXLABackend: on_start: Trace: Started.")
        return super().on_start(worker_group, backend_config)

    def on_training_start(
        self, worker_group: WorkerGroup, backend_config: TorchXLAConfig
    ):
        """
        Configure the environment variables for the worker group.
        And initialize the xla distributed process group.
        TODO: Current setup only supports homogenous cluster with
         neuron_cores accelerator and xrt runtime.
        """
        print (f"ray_neuron_xla_config_20: _NewTorchAwsNeuronXLABackend: on_training_start: Trace: Started.")
        worker_group.execute(_set_xla_env_vars)
        worker_group.execute(_setup_xla_torch_process_group)


