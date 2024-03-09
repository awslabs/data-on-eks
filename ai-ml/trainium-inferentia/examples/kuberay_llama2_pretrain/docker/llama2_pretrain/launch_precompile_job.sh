#!/bin/bash

NEURON_NUM_DEVICES=32 python3 ray_train_llama2.py --neuron_parallel_compile
