#!/usr/bin/env python3
"""Run a benchmark script as a Ray task inside the current Ray job.

The benchmark clients are plain HTTP clients. Running them through ray.init()
and a Ray task registers a driver job, the task and its logs with Ray, so the
Ray Dashboard and the Ray History Server show the job after the cluster is gone.

Usage: python ray_job_wrapper.py <script.py> [script args]
"""
import runpy
import sys

import ray


@ray.remote(num_cpus=0.5)
def run_benchmark(script, argv):
    sys.argv = [script] + argv
    try:
        runpy.run_path(script, run_name="__main__")
    except SystemExit as e:
        if e.code not in (None, 0):
            raise
    return script


if __name__ == "__main__":
    ray.init()
    print("finished:", ray.get(run_benchmark.remote(sys.argv[1], sys.argv[2:])), flush=True)
