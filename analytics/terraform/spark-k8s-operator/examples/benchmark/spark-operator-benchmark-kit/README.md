# Spark-Operator Benchmark kit

## Getting started
Locust creates User processes that execute Tasks based on the configuration in the `locustfile.py` file. This allows us to create SparkApplication CRDs at a consistent rate and scale.  

### Install locust
```
python3.12 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### Run locust
#### Web UI
Running locust without parameters will launch a webui at [http://0.0.0.0:8089](http://0.0.0.0:8089):  
```bash
locust
```
From there you can configure the parameters in the web form and start the test.

#### Without GUI/Headless
Providing the `--headless` option disables the webui and instead runs automatically with the default parameters:  
```bash
locust --headless --only-summary -u 1 -r 1
```
This starts a single User over 1s.

```bash
locust --headless --only-summary -u 3 -r 1 --job-limit 2000 --jobs-per-min 1000 --spark-namespaces spark-team-a,spark-team-b,spark-team-c
```

This runs 6000 jobs over three namespaces ('`spark-team-a`, `spark-team-b`, `spark-team-c`) with 1000 submissions per minute (limited by CPU).


#### Parameters
**Spark test options:**

```bash
  --spark-template SPARK_TEMPLATE
                        Path to SparkApplication template
  --spark-name-prefix SPARK_NAME_PREFIX
                        Prefix for generated names
  --spark-name-length SPARK_NAME_LENGTH
                        Length of random name suffix
  --job-limit JOB_LIMIT
                        Maximum number of applications to submit per user
  --jobs-max-failures JOBS_MAX_FAILURES
                        Maximum number of failures before stopping
  --jobs-per-min JOBS_PER_MIN
                        Submissions per minute
  --spark-namespaces SPARK_NAMESPACES
                        Comma-separated list of namespaces (e.g., spark-team-a,spark-team-b)
  --no-spark-cleanup    If set, Spark applications will not be deleted after test
```

**Common options:**
```bash
  -u, --users <int>     Peak number of concurrent Locust users. Primarily used together with --headless or --autostart. Can be changed during a test by keyboard inputs w, W (spawn 1, 10 users) and s, S (stop 1, 10 users)
  -r, --spawn-rate <float>
                        Rate to spawn users at (users per second). Primarily used together with --headless or --autostart
  -t, --run-time <time string>
                        Stop after the specified amount of time, e.g. (300s, 20m, 3h, 1h30m, etc.). Only used together with --headless or --autostart. Defaults to run forever.
  --only-summary        Disable periodic printing of request stats during --headless run
```

When determining the load to apply, the number of users and job submission rate are multiplicative. i.e.: 
```
Num Users * Jobs per Min = total submission rate
```
and 
```
Num Users * Jobs Limit = total number of jobs
```

**Examples**
To submit 50 Jobs as fast as possible with a single process:
```bash
locust --headless --only-summary -u 1 -r 1 --jobs-per-min -1 --jobs-limit 50
```
You can increase the rate at which calls are made by increasing the number of users spawned (concurrency). 
```bash
locust --headless --only-summary -u 1 -r 1 --jobs-per-min -1 --jobs-limit 50
```

Submit 30 jobs a minute, until 100 jobs are submitted with both of these commands below
```bash
locust --headless --only-summary -u 1 -r 1 --jobs-per-min 30 --jobs-limit 100
```
or 
```bash
locust --headless --only-summary -u 2 -r 1 --jobs-per-min 15 --jobs-limit 50
```

To run the same test 3 times in a row with sleep in between
```bash
JOBS_MIN=-1
JOBS_LIMIT=10
TIMEOUT="7m"
USERS=1
RATE=1

sleep 240
locust --headless --only-summary -u $USERS -r $RATE -t $TIMEOUT --jobs-per-min $JOBS_MIN --jobs-limit $JOBS_LIMIT 2>&1 | tee -a load-test-$(date -u +"%Y-%m-%dT%H:%M:%SZ").log 

echo "\n~~~~~~~~~~~~~~~~~~~~~~~Sleeping for 3min to separate tests~~~~~~~~~~~~~~~~~~~~~~\n"
sleep 240

locust --headless --only-summary -u $USERS -r $RATE -t $TIMEOUT --jobs-per-min $JOBS_MIN --jobs-limit $JOBS_LIMIT 2>&1 | tee -a load-test-$(date -u +"%Y-%m-%dT%H:%M:%SZ").log

echo "\n~~~~~~~~~~~~~~~~~~~~~~~Sleeping for 3min to separate tests~~~~~~~~~~~~~~~~~~~~~~\\n"
sleep 240

locust --headless --only-summary -u $USERS -r $RATE -t $TIMEOUT --jobs-per-min $JOBS_MIN --jobs-limit $JOBS_LIMIT 2>&1 | tee -a load-test-$(date -u +"%Y-%m-%dT%H:%M:%SZ").log
```

to delete all of the nodes in the Spark ASG and start fresh you can run: 
```bash
for ID in $(aws autoscaling describe-auto-scaling-instances --output text \
--query "AutoScalingInstances[?AutoScalingGroupName=='eks-spark_benchmark_ebs-20250203215338743800000001-aeca66e7-0385-19a7-a895-d021a5f67933'].InstanceId");
do
aws ec2 terminate-instances --instance-ids $ID
done
```

## Test Spark Application

Source code and steps to build the the Spark Application used for testing are available [here](./spark-pi-sleep).


