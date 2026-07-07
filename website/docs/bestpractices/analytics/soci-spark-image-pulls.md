---
sidebar_position: 6
sidebar_label: Faster Spark Image Pulls with SOCI
---

# Accelerating Spark Image Pulls on EKS with SOCI Parallel Pull

Spark on Kubernetes has an image pull problem that most teams discover the hard way. Spark images are big. Whether you run the open source `apache/spark` image, Amazon EMR on EKS Spark, or a custom image built on either, 3 to 5 GB compressed is common once you layer in connectors, application jars, and Python dependencies. Every time Karpenter provisions a fresh node for a burst of executors, the first pod on that node has to download and unpack the full image before a single task runs.

With default containerd behavior, that cold-pull wait can run to tens of seconds per node, longer for larger images. For a job that scales out to dozens of nodes, you pay that penalty on every fresh node, and your job's time to first task is gated by it. Autoscaling responsiveness, Spot interruption recovery, and cost all suffer because nodes sit idle while pulling.

The fix is not lazy loading, a bigger instance, or a faster registry. It is parallelizing the pull itself.

:::info

This guide uses Spark as the worked example because its autoscaling and executor-burst pattern makes cold pulls especially painful. SOCI parallel pull operates at the container runtime and registry layer, so it is image- and application-agnostic. Nothing here is specific to EMR on EKS or even to Spark. The same feature gate and configuration accelerate any large image, including Flink, Trino, Ray, and ML/inference containers. Where the guidance below is genuinely Spark-shaped (classpath behavior, `spark.jars`), it is called out.

:::

## Why default image pulls are slow

An image pull has two phases: downloading compressed layers from the registry, and unpacking them to disk. Stock containerd downloads each layer over a single HTTP connection and unpacks layers mostly serially. Neither phase saturates the hardware. A single connection to ECR often sustains only a few hundred Mbps, far below the bandwidth a modern node has available, so the download is connection-bound rather than bandwidth-bound.

Layer structure makes this worse for large JVM images. They tend to concentrate most of their bytes in one or two fat layers. Inspecting the EMR on EKS 7.12.0 base image, for example, shows a single layer of roughly 1.2 GB, about 40 percent of the whole image. On a single connection, that one layer dominates the pull, and extra node bandwidth does nothing to help.

```bash
# EMR on EKS base images are on the public ECR gallery (6.9.0+), so this
# needs no auth. For any other image, point the command at your own tag.
docker manifest inspect public.ecr.aws/emr-on-eks/spark/emr-7.12.0:latest
# This image: 25 layers, ~3 GB compressed, with a single dominant ~1.2 GB layer.
```

## SOCI parallel pull mode

The [SOCI snapshotter](https://github.com/awslabs/soci-snapshotter) added a parallel pull and unpack mode in **v0.11.0**. It splits large layers into chunks, downloads the chunks over many concurrent HTTP connections, and unpacks multiple layers at once. This is not lazy loading. It is a full, up-front pull that parallelizes the work. There is no image rebuild, no SOCI index artifacts, and no pipeline changes. It works on your existing images, from any registry, for any workload.

Recent Amazon EKS optimized AMIs for **Amazon Linux 2023 and Bottlerocket** ship the snapshotter built in, enabled through the `FastImagePull` nodeadm feature gate. `FastImagePull` is currently marked **experimental** by the EKS AMI project, so validate it on a staging node pool before rolling it out broadly. In our testing with a ~3 GB Spark image, enabling parallel pull together with the storage configuration below produced a large reduction in cold-pull time on fresh nodes.

One mental model before tuning: images are cached per node. Only the first pod on a fresh node pulls. Every subsequent executor scheduled to that node starts from cache in well under a second. All of this optimization targets the cold pull on new nodes, which is exactly where Spark autoscaling hurts.

## Karpenter configuration for SOCI

Everything lives in the Karpenter `EC2NodeClass`. This single configuration handles fleets with and without NVMe instance store.

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: spark-soci
spec:
  amiSelectorTerms:
    - alias: al2023@latest
  # On instances with NVMe instance store, nodeadm assembles a RAID0
  # and mounts it at /var/lib/containerd, so SOCI unpacks to local
  # NVMe instead of EBS. No-op on instances without instance store.
  instanceStorePolicy: RAID0
  # Covers instances without NVMe. Parallel pull moves the bottleneck
  # from network to disk; the default 125 MiB/s gp3 volume will cap
  # your gains almost entirely.
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 200Gi
        volumeType: gp3
        iops: 16000
        throughput: 1000
        encrypted: true
        deleteOnTermination: true
  userData: |
    MIME-Version: 1.0
    Content-Type: multipart/mixed; boundary="BOUNDARY"

    --BOUNDARY
    Content-Type: application/node.eks.aws
    ---
    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      featureGates:
        # Experimental. Activates the SOCI snapshotter's parallel
        # pull/unpack mode. Ignored on instances below the size
        # threshold (see tuning notes).
        FastImagePull: true
      kubelet:
        config:
          # Helps when driver, executor, and DaemonSet images pull
          # concurrently on a fresh node. Identical-image pulls are
          # already deduplicated by kubelet.
          serializeImagePulls: false
          maxParallelImagePulls: 5
          registryPullQPS: 50
          registryBurst: 100
      containerd:
        config: |
          [plugins."io.containerd.snapshotter.v1.soci"]
            [plugins."io.containerd.snapshotter.v1.soci".blob]
              # -1 removes node-level caps so per-image limits govern
              max_concurrent_downloads = -1
              max_concurrent_unpacks = -1
              # 20 connections and 16mb chunks are the recommended
              # band for ECR (default is 3 per image). A 1.2 GB layer
              # then splits into ~80 chunks.
              max_concurrent_downloads_per_image = 20
              concurrent_download_chunk_size = "16mb"
              # Match to the count of meaningful layers in your image
              max_concurrent_unpacks_per_image = 12
              # Drop compressed blobs after unpack to save disk. Safe
              # for pull-only nodes; skip it if you build, push, or
              # export images from the node, or run multiple snapshotters.
              discard_unpacked_layers = true
    --BOUNDARY--
```

## Tuning notes

**Instance size matters.** `FastImagePull` is silently ignored below a vCPU and memory threshold. AWS currently recommends 2xlarge or larger, and that value may change. If your NodePool allows xlarge or smaller, those nodes fall back to standard pulls and you will see bimodal pull times across the fleet. Constrain instance sizes or accept the inconsistency knowingly.

**Storage is the second bottleneck.** Once downloads are parallel, disk writes become the limit. Prefer instance families with NVMe instance store (c5d, m5d, r5d, m6id, and similar) for Spark nodes; you likely want local NVMe for shuffle anyway. Where NVMe is not available, the gp3 throughput and IOPS in the config above are not optional. AWS recommends at least 600 MiB/s, with 1000 MiB/s and 16k IOPS giving better results.

**Tune to your layer structure, not a formula.** `max_concurrent_unpacks_per_image` beyond your count of non-trivial layers buys nothing. The EMR 7.12.0 base image has roughly a dozen meaningful layers out of 25, so 12 is a reasonable ceiling for it. Check your own image with `docker manifest inspect`.

**The floor is the biggest layer's unpack.** Decompression of a single layer is one stream. A 1.2 GB layer's unpack is CPU and disk bound and cannot be parallelized further. If you control the Dockerfile, splitting one giant layer into several medium ones helps both download and unpack.

## Should you enable lazy loading?

No, not for Spark. Lazy loading does not eliminate download time; it moves it from pod startup into task runtime through a FUSE filesystem. A Spark JVM reads nearly its entire classpath at startup, so the working set is effectively the whole image. You would pay the same download cost spread across task execution, plus FUSE overhead, a runtime dependency on the registry, and the operational cost of building SOCI index artifacts for every image you ship.

The same reasoning applies to other JVM-based engines. Flink and Trino also load large classpaths at startup, as do batch and compute workloads in general, whose entrypoint touches most of the image. Lazy loading is designed for services whose entrypoint touches a small fraction of the image. Batch compute is the opposite profile. Use parallel pull mode.

## Verifying it works

On a fresh node, before trusting benchmark numbers:

```bash
# Parallel pull activity in the snapshotter logs
journalctl -u soci-snapshotter | grep -i parallel

# On NVMe instances, containerd state should sit on the RAID0 mount
df -h /var/lib/containerd

# Pull duration from the pod event
kubectl describe pod <pod> | grep -A1 Pulled
```

The most common failure mode is a PoC run on an instance below the size threshold, where the feature gate no-ops and results look identical to baseline.

## Beyond SOCI

Parallel pull attacks the pull. These attack the problem around it, roughly in order of impact:

**Slim your custom layers.** Your base image is fixed, but everything you add on top is yours to cut. For Spark, ship application jars and Python dependencies from S3 via `spark.jars` and `--py-files` instead of baking them into the image. Anything removed comes straight off every cold pull. See [Loading Spark dependencies from S3](#loading-spark-dependencies-from-s3) below for concrete examples.

**Extend node lifetime.** Review Karpenter consolidation and `expireAfter` settings. Longer lived nodes mean more cache hits and fewer cold pulls. If nodes churn every few minutes, pull time dominates regardless of how fast the pull is.

**Watch baseline network bandwidth.** At parallel pull speeds, smaller instances become network bound once ENA burst credits deplete. Baseline bandwidth, not burst, is what sustained scale-out sees.

**Pre-baked EBS snapshots** with the image already cached, referenced in `blockDeviceMappings`, take pulls to near zero. The trade is a snapshot lifecycle per image release. Worth it only when the image changes rarely.

Keep ECR in the same region as the cluster with a VPC endpoint. This is table stakes, but it still gets missed.

## Loading Spark dependencies from S3

The biggest lever on cold-pull time you actually control is what you bake into the image. A connector, an application jar, and a few Python libraries can easily add a gigabyte that every fresh node re-pulls. Spark can fetch all of it from S3 at submit time instead, so those bytes never touch the image.

Spark's `--jars`, `--py-files`, and `--files` options accept any Hadoop-supported URI scheme, including `s3a://`. The driver and every executor download the referenced objects at startup and add jars to the classpath. The job's own artifact (the main jar or `.py` file) can live on S3 too.

:::warning The one thing you must keep in the image

The S3A filesystem client (`hadoop-aws` plus a matching AWS SDK, or EMRFS on EMR on EKS images) has to already be on the classpath, because Spark needs it to read S3 in the first place. You cannot bootstrap the S3 connector from S3. EMR on EKS base images include this; the plain `apache/spark` image does not, so add it there. Everything above the filesystem client is fair game to externalize.

:::

Give the pods an IAM role via IRSA or EKS Pod Identity with `s3:GetObject` on the bucket, then reference the objects by URI.

### With `spark-submit`

```bash
spark-submit \
  --master k8s://https://<eks-api-server> \
  --deploy-mode cluster \
  --conf spark.kubernetes.container.image=<your-slim-image> \
  --conf spark.kubernetes.authenticate.driver.serviceAccountName=<irsa-sa> \
  --jars s3a://my-bucket/jars/connector.jar,s3a://my-bucket/jars/app-deps.jar \
  --py-files s3a://my-bucket/py/deps.zip \
  --files s3a://my-bucket/conf/log4j2.properties \
  s3a://my-bucket/app/main.py
```

### With the Spark Operator (`SparkApplication`)

The operator exposes the same options under `spec.deps`, so the artifacts stay out of the image while the manifest stays declarative.

```yaml
apiVersion: sparkoperator.k8s.io/v1beta2
kind: SparkApplication
metadata:
  name: etl-job
spec:
  type: Python
  mode: cluster
  image: <your-slim-image>
  mainApplicationFile: s3a://my-bucket/app/main.py
  deps:
    jars:
      - s3a://my-bucket/jars/connector.jar
      - s3a://my-bucket/jars/app-deps.jar
    pyFiles:
      - s3a://my-bucket/py/deps.zip
    files:
      - s3a://my-bucket/conf/log4j2.properties
  driver:
    serviceAccount: <irsa-sa>   # role with s3:GetObject on the bucket
  executor:
    instances: 50
```

### Pulling from Maven instead

If a dependency is published to a Maven repository, `spark.jars.packages` (or `--packages`) resolves it and its transitive jars at startup, with no image bytes at all.

```bash
--packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0
```

The trade-off is real: every driver and executor runs Ivy resolution at startup and reaches out to a Maven repository, which adds latency and a network dependency at exactly the moment you are trying to start fast. For a large scale-out, pre-stage the resolved jars in S3 and use `--jars s3a://...` instead. Reserve `--packages` for iteration and low-fan-out jobs. If you do use it, point `spark.jars.ivy` at a writable path (for example `/tmp/.ivy2`) and consider an internal mirror.
