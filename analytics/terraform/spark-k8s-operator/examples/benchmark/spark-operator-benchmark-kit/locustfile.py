import copy
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
from locust import HttpUser, task, env, events, constant


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


@events.init_command_line_parser.add_listener
def on_parser_init(parser):
    parser.add_argument(
        "--spark-template",
        help="Path to SparkApplication template",
        env_var="LOAD_TEST_TEMPLATE_PATH",
        default="spark-app-template.yaml"
    )
    parser.add_argument(
        "--spark-name-prefix",
        help="Prefix for generated names",
        env_var="LOAD_TEST_NAME_PREFIX",
        default="load-test"
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
        default="default"
    )
    parser.add_argument(
        "--no-spark-cleanup",
        action="store_true",
        help="If set, Spark applications will not be deleted after test",
        env_var="LOAD_TEST_NO_CLEANUP",
        default=False
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
        template["metadata"]["name"] = variables["name"]
        template["metadata"]["namespace"] = variables["namespace"]
        template["spec"]["sparkConf"]["spark.kubernetes.executor.podNamePrefix"] = variables["name"]
        template["spec"]["driver"]["serviceAccount"] = variables["namespace"] # assume namespace and service account match
        return template


class SparkLoadTest(HttpUser):
    # may not be necessary
    host = "http://localhost"

    def wait_time(self):
        return constant(60 / self.config.submission_rate)(self)

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
        # self.wait_time = constant(60 / self.config.submission_rate)
        self.failure_count = 0
        self.namespace_index = 0
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
        batch_failures = 0

        try:
            # Select namespace using round-robin
            namespace = self.config.namespaces[self.namespace_index % len(self.config.namespaces)]

            name = generate_spark_name(
                prefix=self.config.name_prefix,
                length=self.config.name_suffix_length
            )

            spec = self.template_manager.substitute_variables({
                "name": name,
                "namespace": namespace
            })

            self.logger.info(f"Submitting Spark application: {name} to namespace: {namespace}")
            self.k8s_client.create_spark_application(namespace, name, spec["spec"])
            self.application_count += 1
            self.namespace_index += 1

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
            batch_failures += 1
            self.logger.error(f"Failed to submit Spark application: {str(e)}")
