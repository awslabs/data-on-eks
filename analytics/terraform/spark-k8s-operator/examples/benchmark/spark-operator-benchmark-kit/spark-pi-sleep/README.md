## Test Spark Application

Source code for the Spark Application used for testing is available in this directory.

You can build your Docker image by following steps below.

### Pre-reqs
- Gradle and Java: https://gradle.org/install/
- Docker (or other container builder): https://docs.docker.com/get-started/get-docker/
  - Docker buildx for cross platform builds: https://github.com/docker/buildx

### Compile

From the [spark-pi-sleep](./spark-pi-sleep/) directory:

```bash
./gradlew build
```

### Build Docker image

From the [docker](./docker/) directory:

```bash
cp ../spark-pi-sleep/build/libs/spark-pi-sleep-1.0.jar spark-pi-sleep.jar
docker build .
```

After building the image you can [push it to an Amazon ECR repo](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-push.html) or your container registry.

### Using the Docker image

You can then specify your image and the sleep duration like below in the Spark Application:

in `spark-app-template.yaml`:
```yaml
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
spec:
  image: public.ecr.aws/data-on-eks/spark:pi-sleep-v0.0.2 # update to your image here
  mainApplicationFile: local:///opt/spark/examples/jars/spark-pi-sleep.jar
  arguments: ["1", "1800"] # sleep for 1800 seconds
```
