#!/bin/bash
set -x #echo on

# $LWS_LEADER_ADDRESS is being updated by LWS manifest deployment
export MASTER_ADDR=$LWS_LEADER_ADDRESS
export NEURON_RT_ROOT_COMM_ID=$LWS_LEADER_ADDRESS:8990
export CPU_COMM_ID=$LWS_LEADER_ADDRESS:8989
export NODE_ADDR=$(hostname)
export GLOBAL_TP=$((WORKER_COUNT * NEURON_LOCAL_TP))
export NEURON_MULTI_NODE=True
export RUN_IN_CONTAINER=True
export RUN_IN_AWS=True

printenv

# Validate vllm installation
echo "Checking for vllm package..."
if pip list | grep vllm; then
    echo "vllm package is installed."
    pip show vllm
else
    echo "ERROR: vllm package is not installed!"
    exit 1
fi

# Run the Python script
python neuron_multi_node_runner.py \
--model=$NEURON_MODEL_PATH \
--max-num-seqs=$MAX_NUM_SEQ \
--max-model-len=$MAX_MODEL_LENGTH \
--block-size=$BLOCK_SIZE \
--tensor-parallel-size=$GLOBAL_TP \
--port=$VLLM_LEADER_SERVICE_PORT \
--swap-space=$SWAP_SPACE
