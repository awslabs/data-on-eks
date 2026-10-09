import copy
import itertools
import os
import re

import yaml
import string
import random
import logging
import time
from typing import Dict, Any, Optional
from dataclasses import dataclass, field

from k8s_client import KubernetesClient
from locust import HttpUser, task, env, events, constant_pacing


@dataclass
class Configuration:

    def __init__(self, environment: env.Environment ):
        parsed = environment.parsed_options
        # Override defaults with environment variables if present
        self.template_path= parsed.spark_template
        self.name_prefix = parsed.spark_name_prefix
        self.name_suffix_length = parsed.spark_name_length
        self.max_jobs = parsed.job_limit_per_user
        self.max_failures = parsed.jobs_max_failures
        self.submission_rate = parsed.jobs_per_min
        self.namespaces = parsed.spark_namespaces.split(",")
        self.cleanup_apps = not parsed.no_spark_cleanup
        self.tpcds_bucket = parsed.tpcds_bucket
        self.tpcds_data_path = parsed.tpcds_data_path.strip("/")
        self.results_bucket = parsed.results_bucket
        self.prefix_count = parsed.prefix_count
        self.tpcds_iterations = parsed.tpcds_iterations
        self.zone = parsed.zone

        # Validate configuration
        self.validate()


    @staticmethod
    def get_parser():
        return events.get_parser()

    def validate(self) -> None:
        if not os.path.exists(self.template_path):
            raise FileNotFoundError(f"Template file not found: {self.template_path}")

        if not re.match(r'^[a-z][-a-z0-9]*$', self.name_prefix):
            raise ValueError("Invalid name_prefix format")

        if self.name_suffix_length < 1:
            raise ValueError("name_suffix_length must be positive")

        if self.max_jobs < 1:
            raise ValueError("job_size must be positive")

        if self.max_failures < 0:
            raise ValueError("max_failures must be non-negative")

        if self.submission_rate <= 0:
            raise ValueError("submission_rate must be positive")

        if not self.namespaces:
            raise ValueError("namespaces list cannot be empty")
        for ns in self.namespaces:
            if not re.match(r'^[a-z0-9][-a-z0-9]*[a-z0-9]$', ns):
                raise ValueError(f"Invalid namespace format: {ns}")

        if not 1 <= self.prefix_count <= 99:
            raise ValueError("prefix_count must be between 1 and 99")

        if self.tpcds_iterations < 1:
            raise ValueError("tpcds_iterations must be positive")

        if self.zone and not re.match(r'^[a-z]{2}-[a-z]+-\d[a-z]$', self.zone):
            raise ValueError(f"Invalid zone format: {self.zone}")


@events.init_command_line_parser.add_listener
def on_parser_init(parser):
    parser.add_argument(
        "--spark-template",
        help="Path to SparkApplication template",
        env_var="LOAD_TEST_TEMPLATE_PATH",
        default="tpcds-sf30-template.yaml"
    )
    parser.add_argument(
        "--spark-name-prefix",
        help="Prefix for generated names",
        env_var="LOAD_TEST_NAME_PREFIX",
        default="tpcds"
    )
    parser.add_argument(
        "--spark-name-length",
        type=int,
        help="Length of random name suffix",
        env_var="LOAD_TEST_NAME_SUFFIX_LENGTH",
        default=8
    )
    parser.add_argument(
        "--job-limit-per-user",
        type=int,
        help="Maximum number of applications to submit per user",
        env_var="LOAD_TEST_JOB_SIZE",
        default=3
    )
    parser.add_argument(
        "--jobs-max-failures",
        type=int,
        help="Maximum number of failures before stopping",
        env_var="LOAD_TEST_MAX_FAILURES",
        default=5
    )
    parser.add_argument(
        "--jobs-per-min",
        type=float,
        help="Submissions per minute",
        env_var="LOAD_TEST_SUBMISSION_RATE",
        default=10.0
    )
    parser.add_argument(
        "--spark-namespaces",
        help="Comma-separated list of namespaces (e.g., spark-team-a,spark-team-b)",
        env_var="LOAD_TEST_NAMESPACES",
        default="spark-team-a"
    )
    parser.add_argument(
        "--no-spark-cleanup",
        action="store_true",
        help="If set, Spark applications will not be deleted after test",
        env_var="LOAD_TEST_NO_CLEANUP",
        default=False
    )
    parser.add_argument(
        "--tpcds-bucket",
        help="S3 bucket with the TPC-DS source data",
        env_var="LOAD_TEST_TPCDS_BUCKET",
        default="spark-scaletest-eks-tpcds-us-west-2"
    )
    parser.add_argument(
        "--tpcds-data-path",
        help="Path of the TPC-DS data under each prefix (s3a://<bucket>/cNN/<path>)",
        env_var="LOAD_TEST_TPCDS_DATA_PATH",
        default="tpcds/sf30"
    )
    parser.add_argument(
        "--results-bucket",
        help="S3 bucket for the query results",
        env_var="LOAD_TEST_RESULTS_BUCKET",
        default="spark-on-eks-spark-logs-344a3629d86dbc9b12395e5b87"
    )
    parser.add_argument(
        "--prefix-count",
        type=int,
        help="Number of cNN prefixes (c01 to cNN) in the source and results buckets",
        env_var="LOAD_TEST_PREFIX_COUNT",
        default=50
    )
    parser.add_argument(
        "--tpcds-iterations",
        type=int,
        help="TPC-DS iterations per application",
        env_var="LOAD_TEST_TPCDS_ITERATIONS",
        default=4
    )
    parser.add_argument(
        "--zone",
        help="Availability Zone for driver and executor pods (for example us-west-2a). Empty: any zone",
        env_var="LOAD_TEST_ZONE",
        default=""
    )


@events.quitting.add_listener
def clean_up_spark_applications(environment: env.Environment, **kwargs):
    logger = logging.getLogger("cleanup")
    if environment.parsed_options.no_spark_cleanup:
        logger.info("Skipping cleanup")
        return

    logger.info(f"Cleaning up spark applications. namespaces={environment.parsed_options.spark_namespaces}")
    k8s_client = KubernetesClient()
    try:
        for namespace in environment.parsed_options.spark_namespaces.split(","):
            logger.info(f"Cleaning up spark applications in namespace {namespace}")
            k8s_client.delete_namespace_spark_application(namespace)
    except Exception as e:
        logger.error(f"Cleanup failed: {str(e)}")


def generate_spark_name(prefix: str = "load-test", length: int = 8) -> str:
    if length < 1:
        raise ValueError("Length must be positive")
    if not prefix or not re.match(r'^[a-z][-a-z0-9]*$', prefix):
        raise ValueError(
            "Prefix must start with lowercase letter and contain only lowercase letters, numbers, and hyphens")

    chars = string.ascii_lowercase + string.digits
    suffix = ''.join(random.choice(chars) for _ in range(length))
    return f"{prefix}-{suffix}"


def validate_spark_name(name: str) -> bool:
    pattern = r'^load-test-[a-z0-9]+$'
    return bool(re.match(pattern, name))


# Shared by all users: per-user counters would send the first submission of every
# user to the same prefix and namespace.
_submission_counter = itertools.count()


class TemplateManager:

    def __init__(self, template_path: str):
        self.template_path = template_path
        self.template_content = None
        self.load_template()

    def load_template(self) -> None:
        if not os.path.exists(self.template_path):
            raise FileNotFoundError(f"Template file not found: {self.template_path}")

        try:
            with open(self.template_path, 'r') as f:
                self.template_content = yaml.safe_load(f)

            if not isinstance(self.template_content, dict):
                raise ValueError("Template must be a valid YAML mapping")

        except yaml.YAMLError as e:
            raise ValueError(f"Invalid YAML template: {str(e)}")

    def substitute_variables(self, variables: Dict[str, Any]) -> dict:
        template = copy.deepcopy(self.template_content)
        name = variables["name"]
        namespace = variables["namespace"]
        prefix = variables["prefix"]
        spec = template["spec"]

        template["metadata"]["name"] = name
        template["metadata"]["namespace"] = namespace
        spec["sparkConf"]["spark.kubernetes.executor.podNamePrefix"] = name
        # Assumes the service account has the same name as the namespace.
        spec["driver"]["serviceAccount"] = namespace
        spec["executor"]["serviceAccount"] = namespace

        # Argument positions are defined by com.k8s.spark.benchmark.BenchmarkSQL.
        spec["arguments"][0] = f"s3a://{variables['tpcds_bucket']}/{prefix}/{variables['tpcds_data_path']}"
        spec["arguments"][1] = f"s3a://{variables['results_bucket']}/{prefix}/tpcds-results/{name}"
        spec["arguments"][5] = str(variables["iterations"])

        if variables.get("zone"):
            for role in ("driver", "executor"):
                terms = spec[role]["template"]["spec"]["affinity"]["nodeAffinity"][
                    "requiredDuringSchedulingIgnoredDuringExecution"]["nodeSelectorTerms"]
                # Terms are ORed, so the zone must be in every term.
                for term in terms:
                    term.setdefault("matchExpressions", []).append({
                        "key": "topology.kubernetes.io/zone",
                        "operator": "In",
                        "values": [variables["zone"]],
                    })
        return template


class SparkLoadTest(HttpUser):
    # may not be necessary
    host = "http://localhost"

    def wait_time(self):
        # Pacing, not a fixed sleep: the submission call time must not lower the rate.
        return constant_pacing(60 / self.config.submission_rate)(self)

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.logger = logging.getLogger()
        self.config = Configuration(self.environment)

        self.logger.setLevel(logging.INFO)
        if not self.logger.handlers:
            handler = logging.StreamHandler()
            formatter = logging.Formatter(
                '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
            )
            handler.setFormatter(formatter)
            self.logger.addHandler(handler)

        self.template_manager = TemplateManager(self.config.template_path)
        self.failure_count = 0
        self.application_count = 0

        self.k8s_client = KubernetesClient()


    def on_start(self):
        try:
            for namespace in self.config.namespaces:
                if not self.k8s_client.namespace_exists(namespace):
                    self.logger.error(f"Namespace {namespace} does not exist. Please ensure it exists.")
                    raise ValueError(f"Namespace {namespace} does not exist")
        except Exception as e:
            self.environment.runner.quit()
            raise


    @task(1)
    def submit_spark_applications(self):
        if self.failure_count >= self.config.max_failures:
            self.logger.error(f"Failure threshold reached ({self.failure_count} failures)")
            self.environment.runner.quit()
            return

        if self.application_count >= self.config.max_jobs:
            self.logger.info("Maximum job count reached")
            self.stop()
            return

        submission_start_time = time.time()

        try:
            n = next(_submission_counter)
            namespace = self.config.namespaces[n % len(self.config.namespaces)]
            prefix = f"c{(n % self.config.prefix_count) + 1:02d}"

            name = generate_spark_name(
                prefix=self.config.name_prefix,
                length=self.config.name_suffix_length
            )

            spec = self.template_manager.substitute_variables({
                "name": name,
                "namespace": namespace,
                "prefix": prefix,
                "tpcds_bucket": self.config.tpcds_bucket,
                "tpcds_data_path": self.config.tpcds_data_path,
                "results_bucket": self.config.results_bucket,
                "iterations": self.config.tpcds_iterations,
                "zone": self.config.zone,
            })

            self.logger.info(f"Submitting Spark application: {name} to namespace: {namespace} prefix: {prefix}")
            self.k8s_client.create_spark_application(namespace, name, spec["spec"])
            self.application_count += 1

            # TODO need to rework on stats
            submission_response_time = (time.time() - submission_start_time) * 1000
            self.environment.events.request.fire(
                request_type="SparkApplication",
                name="application_created",
                response_time=submission_response_time,
                response_length=0,
                exception=None
            )

        except Exception as e:
            self.failure_count += 1
            self.logger.error(f"Failed to submit Spark application: {str(e)}")
            self.environment.events.request.fire(
                request_type="SparkApplication",
                name="application_created",
                response_time=(time.time() - submission_start_time) * 1000,
                response_length=0,
                exception=e
            )
