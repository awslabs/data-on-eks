import logging
from typing import Optional
from kubernetes import client, config
from kubernetes.client.rest import ApiException

class KubernetesClient:

    def __init__(self, context: Optional[str] = None):
        self.logger = logging.getLogger(__name__)
        self._setup_logging()
        self._initialize_client(context)
        self.custom_api = client.CustomObjectsApi()

    def _setup_logging(self) -> None:
        self.logger = logging.getLogger("k8s_client")
        self.logger.setLevel(logging.INFO)

    def _initialize_client(self, context: Optional[str]) -> None:
        try:
            if context:
                self.logger.debug(f"Loading kube config with context: {context}")
                config.load_kube_config(context=context)
            else:
                try:
                    self.logger.debug("Attempting to load in-cluster config")
                    config.load_incluster_config()
                except config.ConfigException:
                    self.logger.debug("Falling back to kube config file")
                    config.load_kube_config()

            self.core_api = client.CoreV1Api()
            self.logger.debug("Successfully initialized Kubernetes client")

        except Exception as e:
            self.logger.error(f"Failed to initialize Kubernetes client: {str(e)}")
            raise RuntimeError(f"Could not initialize Kubernetes client: {str(e)}")

    def namespace_exists(self, namespace: str) -> bool:
        try:
            self.core_api.read_namespace(namespace)
            return True
        except ApiException as e:
            if e.status == 404:
                return False
            raise RuntimeError(f"Failed to check namespace {namespace}: {str(e)}")

    def create_namespace(self, namespace: str) -> None:
        try:
            if self.namespace_exists(namespace):
                self.logger.info(f"Namespace {namespace} already exists")
                return

            body = client.V1Namespace(
                metadata=client.V1ObjectMeta(name=namespace)
            )
            self.core_api.create_namespace(body=body)
            self.logger.info(f"Created namespace: {namespace}")

        except Exception as e:
            raise RuntimeError(f"Failed to create namespace {namespace}: {str(e)}")

    def create_spark_application(self, namespace: str, name: str, spec: dict) -> dict:
        try:
            self.logger.debug(f"Creating SparkApplication: {name} in namespace: {namespace}")

            body = {
                "apiVersion": "sparkoperator.k8s.io/v1beta2",
                "kind": "SparkApplication",
                "metadata": {
                    "name": name,
                    "namespace": namespace
                },
                "spec": spec
            }

            return self.custom_api.create_namespaced_custom_object(
                group="sparkoperator.k8s.io",
                version="v1beta2",
                namespace=namespace,
                plural="sparkapplications",
                body=body
            )

        except Exception as e:
            self.logger.error(f"Failed to create SparkApplication {name}: {str(e)}")
            raise RuntimeError(f"Failed to create SparkApplication: {str(e)}")

    def get_spark_application(self, namespace: str, name: str) -> Optional[dict]:
        try:
            return self.custom_api.get_namespaced_custom_object(
                group="sparkoperator.k8s.io",
                version="v1beta2",
                namespace=namespace,
                plural="sparkapplications",
                name=name
            )
        except ApiException as e:
            if e.status == 404:
                return None
            self.logger.error(f"Failed to get SparkApplication {name}: {str(e)}")
            raise RuntimeError(f"Failed to get SparkApplication: {str(e)}")

    def delete_spark_application(self, namespace: str, name: str) -> None:
        try:
            self.logger.debug(f"Deleting SparkApplication: {name} from namespace: {namespace}")
            self.custom_api.delete_namespaced_custom_object(
                group="sparkoperator.k8s.io",
                version="v1beta2",
                namespace=namespace,
                plural="sparkapplications",
                name=name
            )
        except ApiException as e:
            if e.status != 404:  # Ignore if already deleted
                self.logger.error(f"Failed to delete SparkApplication {name}: {str(e)}")
                raise RuntimeError(f"Failed to delete SparkApplication: {str(e)}")

    def list_spark_applications(self, namespace: str, label_selector: Optional[str] = None) -> list:
        try:
            response = self.custom_api.list_namespaced_custom_object(
                group="sparkoperator.k8s.io",
                version="v1beta2",
                namespace=namespace,
                plural="sparkapplications",
                label_selector=label_selector
            )
            return response["items"]
        except Exception as e:
            self.logger.error(f"Failed to list SparkApplications: {str(e)}")
            raise RuntimeError(f"Failed to list SparkApplications: {str(e)}")

    def get_spark_application_status(self, namespace: str, name: str) -> Optional[dict]:
        app = self.get_spark_application(namespace, name)
        if not app or "status" not in app:
            return None

        status = app["status"]
        return {
            "state": status.get("applicationState", {}).get("state"),
            "submission_time": status.get("lastSubmissionAttemptTime"),
            "termination_time": status.get("terminationTime"),
            "failure_message": status.get("applicationState", {}).get("errorMessage")
        }

    def delete_namespace_spark_application(self, namespace):
        # delete ALL matching objects in the
        # TODO: this is a bit overkill, we should scope this to only the jobs submitted by this User
        return self.custom_api.delete_collection_namespaced_custom_object(
            group="sparkoperator.k8s.io",
            version="v1beta2",
            namespace=namespace,
            plural="sparkapplications",
        )
