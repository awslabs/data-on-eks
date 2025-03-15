#!/bin/bash

export BASE_DIR="/shared/finetuned_models"
export OUTPUT_DIR=`date "+%Y%m%d_%H%M%S"`

torchrun \
    --nproc_per_node=32 \
    finetune_llama.py \
    --output_dir $BASE_DIR/$OUTPUT_DIR \
    --tensor_parallel_size 8 \
    --bf16 True \
    --per_device_train_batch_size 8 \
    --gradient_accumulation_steps 1 \
    --gradient_checkpointing True \
    --max_steps 250 \
    --logging_steps 10 \
    --learning_rate 1e-5 \
    --dataloader_drop_last True

echo "Output dir = $BASE_DIR/$OUTPUT_DIR"
