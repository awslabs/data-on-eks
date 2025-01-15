from typing import Callable, Dict, Tuple

from pytorch_lightning import LightningDataModule


class NeuronLightningDataModule(LightningDataModule):
    def __init__(
        self,
        dataloader_fn: Callable,
        data_dir: str,
        batch_size: int,
        data_args: Tuple = (),
        data_kwargs: Dict = {},
    ):
        super().__init__()
        self.dataloader_fn = dataloader_fn
        self.data_dir = data_dir
        self.batch_size = batch_size
        self.data_args = (data_args,)
        self.data_kwargs = data_kwargs

    def setup(self, stage: str):
        pass

    def train_dataloader(self):
        return self.dataloader_fn(
            self.data_dir,
            self.batch_size,
            self.trainer.strategy.data_parallel_size,
            self.trainer.strategy.data_parallel_rank,
            *self.data_args,
            **self.data_kwargs
        )[0]

    def test_dataloader(self):
        return self.dataloader_fn(
            self.data_dir,
            self.batch_size,
            self.trainer.strategy.data_parallel_size,
            self.trainer.strategy.data_parallel_rank,
            *self.data_args,
            **self.data_kwargs
        )[1]

