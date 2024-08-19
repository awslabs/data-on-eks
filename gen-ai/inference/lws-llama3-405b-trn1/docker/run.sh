#!/bin/bash

set -x #echo on

# $LWS_LEADER_ADDRESS is being updated by LWS manifest deployment
export MASTER_ADDR=$LWS_LEADER_ADDRESS
export NEURON_RT_ROOT_COMM_ID=$LWS_LEADER_ADDRESS:8990
export CPU_COMM_ID=$LWS_LEADER_ADDRESS:8989
export NODE_ADDR=$(hostname)
export GLOBAL_TP=$((WORKER_COUNT * NEURON_LOCAL_TP))
export AWS_BEDROCK_TP=$((WORKER_COUNT * NEURON_LOCAL_TP))

printenv

export RUN_IN_CONTAINER=True
export RUN_IN_AWS=True
