#!/bin/bash

#############################################
# User defined parameters and env vars

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

export NEURON_CC_FLAGS="--model-type transformer --distribution-strategy=llm-training --cache_dir=/shared/neuron_compile_cache/"
export NEURON_FUSE_SOFTMAX=1

# Async Runtime
export NEURON_RT_ASYNC_EXEC_MAX_INFLIGHT_REQUESTS=3

# HOST OOM
export MALLOC_ARENA_MAX=64

##############################DEFAULT VALUES###########################################
# TP degree
TP_DEGREE=32

KV_REPLI=`expr $TP_DEGREE / 8`
# 0: bf16; 1: mixed precision
USE_MIX_PRECISION=1
# 0: use pure DP; 1: use ZeRO-1
USE_ZERO_1=1
# global batch size
: ${GBS:=1024}
# micro batch size
MBS=1
# number of steps to run
MAX_STEPS=10000
# warmup steps
WARMUP_STEPS=100
# learning rate
#LR=3.0e-4
LR=1.5e-4
# model path
#MODEL_PATH=$SCRIPT_DIR
MODEL_PATH="/shared/llama3.1_config/"
# data path
DATA_PATH="/shared/fineweb_llama3.1_tokenized"
#Checkpoint dir
CKPT_DIR="/shared/checkpoint"
# sequence length
SEQ_LEN=8192
# Number of epochs
EPOCHS=1
#Number of Nodes
NUM_NODES=2
#Tensorboard logs dir
TB_DIR="/shared/tblogs"
#Steps this run
STEPS_THIS_RUN=-1
#output log
ts=`date +%y_%m_%d_%H:%M:%S`
OUTPUT_LOG="/shared/llama3.1-8b-pretrain-$ts.log"
##############################DEFAULT VALUES###########################################

#Args
Help()
{
   # Display Help
   echo "Add description of the script functions here."
   echo
   echo "Syntax: $0 [-t|w|l|m|d|c|s|n]"
   echo "options:"
   echo "t	total number of training steps"
   echo "w	warmup steps for training"
   echo "l	learning rate"
   echo "m	abs path to llama config.json"
   echo "d      abs path to tokenized dataset"
   echo "c     	abs path to checkpoint directory"
   echo "s     	Sequence length"
   echo "n     	Number of instances to run training"
   echo "b      tensor board logs location"
   echo "r      defining steps this run"
   echo
}
while getopts t:w:l:m:d:c:s:n:b:r:h flag
do
    case "${flag}" in
        t) MAX_STEPS=${OPTARG};;
        w) WARMUP_STEPS=${OPTARG};;
        l) LR=${OPTARG};;
        m) MODEL_PATH=${OPTARG};;
        d) DATA_PATH=${OPTARG};;
        c) CKPT_DIR=${OPTARG};;
        s) SEQ_LEN=${OPTARG};;
        n) NUM_NODES=${OPTARG};;
        b) TB_DIR=${OPTARG};;
        r) STEPS_THIS_RUN=${OPTARG};;
	h) Help 
	   exit;;
	#\?) # Invalid option
        #   echo "Error: Invalid option"
        #   exit;;
    esac
done
#############################################

export NUM_NEURONCORES=32
#DISTRIBUTED_ARGS="--nproc_per_node $NUM_NEURONCORES"


#sudo sysctl -w net.ipv4.ip_local_reserved_ports=44000,48620

export NEURON_RT_NUM_CORES=32
export NUM_NEURONCORES=$NEURON_RT_NUM_CORES
export TPU_NUM_DEVICES=$NEURON_RT_NUM_CORES
export TPU_CHIPS_PER_HOST_BOUNDS=$NEURON_RT_NUM_CORES

#############################################


#DP=$(($NEURON_RT_NUM_CORES * $WORLD_SIZE / $TP_DEGREE))
DP=$(($NEURON_RT_NUM_CORES * $NUM_NODES / $TP_DEGREE))
ACC_STEPS=$(($GBS / $MBS / $DP))
#ACC_STEPS=$(($GBS / $MBS / $DP))


echo TP_DEGREE=$TP_DEGREE
echo GBS=$GBS
echo MBS=$MBS
echo MAX_STEPS=$MAX_STEPS
echo WARMUP_STEPS=$WARMUP_STEPS
echo LR=$LR
echo MODEL_PATH=$MODEL_PATH
echo DATA_PATH=$DATA_PATH
echo SEQ_LEN=$SEQ_LEN
echo CKPT_DIR=$CKPT_DIR
echo DP=$DP
echo ACC_STEPS=$ACC_STEPS
echo STEPS_THIS_RUN=$STEPS_THIS_RUN
echo NUM_NODES=$NUM_NODES
echo TB_DIR=$TB_DIR
echo OUTPUT_LOG=$OUTPUT_LOG

neuron_parallel_compile python $DISTRIBUTED_ARGS \
    ray_train_llama3.py \
    --model_path $MODEL_PATH \
    --num_nodes $NUM_NODES \
    --tb_dir $TB_DIR \
    --data_dir $DATA_PATH \
    --tensor_parallel_size $TP_DEGREE \
    --train_batch_size $MBS \
    --steps_this_run $STEPS_THIS_RUN \
    --max_steps $MAX_STEPS \
    --warmup_steps $WARMUP_STEPS \
    --lr $LR \
    --grad_accum_usteps $ACC_STEPS \
    --seq_len $SEQ_LEN \
    --use_sequence_parallel 1 \
    --use_selective_checkpoint 1 \
    --use_fp32_optimizer $USE_MIX_PRECISION \
    --use_zero1_optimizer $USE_ZERO_1 \
    --scheduler_type 'linear' \
    --qkv_linear 1 \
    --kv_replicator $KV_REPLI \
    --num_train_epochs $EPOCHS \
    --save_checkpoint \
    --use_flash_attention 1 |& tee $OUTPUT_LOG
exit ${PIPESTATUS[0]}
