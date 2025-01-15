import os
from typing import Dict
from neuronx_distributed.lightning.strategy import NeuronXLAStrategy
from ray.train.lightning import RayLightningEnvironment
import torch
from lightning_fabric.plugins.environments import (
    TorchElasticEnvironment,
    XLAEnvironment,
)
from lightning_fabric.utilities.types import _PATH, ReduceOp
from pytorch_lightning.strategies import XLAStrategy
from torch import Tensor

from neuronx_distributed.parallel_layers.parallel_state import (
    get_data_parallel_rank,
    get_data_parallel_size,
    get_pipeline_model_parallel_rank,
    get_tensor_model_parallel_rank,
    initialize_model_parallel,
    model_parallel_is_initialized,
)

from neuronx_distributed.lightning.accelerator import NeuronXLAAccelerator
from neuronx_distributed.lightning.checkpoint_io import NeuronCheckpointIO
from neuronx_distributed.lightning.launcher import _NeuronXLALauncher

class RayLightningNeuronXlaStrategy(NeuronXLAStrategy):
    def __init__(
        self,
        nxd_config: Dict = None,
        tensor_parallel_size: int = 1,
        pipeline_parallel_size: int = 1,
        debug: bool = False,
        sync_module_states: bool = False,
        checkpoint_io: bool = None,
        save_load_xser: bool = True,
    ):
        super().__init__(
            nxd_config=nxd_config,
            tensor_parallel_size=tensor_parallel_size,
            pipeline_parallel_size=pipeline_parallel_size,
            debug=debug,
            sync_module_states=sync_module_states,
            checkpoint_io=checkpoint_io,
            save_load_xser=save_load_xser
        )

    def setup_distributed(self) -> None:
        print (f"RayNeuronXLAStrategy TRACE: Got call for setup_distributed, value of {self.parallel_devices=}!")

        super(NeuronXLAStrategy, self).setup_distributed()
        # init model parallel if needed
        if not model_parallel_is_initialized():
            initialize_model_parallel(
                tensor_model_parallel_size=self.tensor_parallel_size,
                pipeline_model_parallel_size=self.pipeline_parallel_size,
            )

        self.data_parallel_rank = get_data_parallel_rank()
        self.data_parallel_size = get_data_parallel_size()
        self.tensor_parallel_rank = get_tensor_model_parallel_rank()
        self.pipeline_parallel_rank = get_pipeline_model_parallel_rank()
        
        
