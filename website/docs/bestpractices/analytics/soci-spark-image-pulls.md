---
sidebar_position: 6
sidebar_label: Faster Spark Image Pulls with SOCI
---

# Accelerating Spark Image Pulls on EKS with SOCI Parallel Pull

Spark on Kubernetes has an image pull problem that most teams discover the hard way. Spark images are big. Whether you run the open source `apache/spark` image, Amazon EMR on EKS Spark, or a custom image built on either, 3 to 5 GB compressed is common once you layer in connectors, application jars, and Python dependencies. Every time Karpenter provisions a fresh node for a burst of executors, the first pod on that node has to download and unpack the full image before a single task runs.

With default containerd behavior, that cold-pull wait can run to tens of seconds per node, longer for larger images. For a job that scales out to dozens of nodes, you pay that penalty on every fresh node, and your job's time to first task is gated by it. Autoscaling responsiveness, Spot interruption recovery, and cost all suffer because nodes sit idle while pulling.

The fix is to parallelize the pull itself.

:::info

This guide uses Spark as the worked example because its autoscaling and executor-burst pattern makes cold pulls especially painful. SOCI parallel pull operates at the container runtime and registry layer, so it is image- and application-agnostic. Nothing here is specific to EMR on EKS or even to Spark. The same feature gate and configuration accelerate any large image, including Flink, Trino, Ray, and ML/inference containers. Where the guidance below is genuinely Spark-shaped (classpath behavior, `spark.jars`), it is called out.

:::

## Why default image pulls are slow

An image pull has two phases: downloading compressed layers from the registry, and unpacking them to disk. Stock containerd downloads each layer over a single HTTP connection and unpacks layers mostly serially. Neither phase saturates the hardware. A single connection to ECR often sustains only a few hundred Mbps, far below the bandwidth a modern node has available, so the download is connection-bound rather than bandwidth-bound.

Layer structure makes this worse for large JVM images. They tend to concentrate most of their bytes in one or two fat layers. Inspecting the EMR on EKS 7.12.0 base image, for example, shows a single layer of roughly 1.2 GB, about 40 percent of the whole image. On a single connection, that one layer dominates the pull, and extra node bandwidth does nothing to help.

```bash
# EMR on EKS base images are on the public ECR gallery (6.9.0+), so this
# needs no auth. Plain `docker manifest inspect` only lists the per-platform
# digests; add --verbose to see each platform's layers and their sizes.
docker manifest inspect --verbose public.ecr.aws/emr-on-eks/spark/emr-7.12.0:latest
# On the linux/amd64 manifest: 25 layers, ~3 GB total, one dominant ~1.2 GB layer.
```

## SOCI parallel pull mode

The [SOCI snapshotter](https://github.com/awslabs/soci-snapshotter) is best known for lazy loading, but its **v0.11.0** parallel pull mode does the opposite. Rather than deferring reads, it runs a complete, up-front pull: it splits large layers into chunks, fetches them over many concurrent HTTP connections, and unpacks several layers at once. Because nothing about the image itself changes, there are no index artifacts to build and no pipeline steps to add, and it works against whatever registry and images you already use.

Recent Amazon EKS optimized AMIs for **Amazon Linux 2023 and Bottlerocket** ship the snapshotter built in, enabled through the `FastImagePull` nodeadm feature gate. `FastImagePull` is currently marked **experimental** by the EKS AMI project, so validate it on a staging node pool before rolling it out broadly. How much this speeds up a cold pull depends on your image's layer layout, the instance size, and the node's disk throughput, so measure it on your own workload using the verification steps below.

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

**Instance size** `FastImagePull` is silently ignored below a vCPU and memory threshold. AWS currently recommends 2xlarge or larger, and that value may change. If your NodePool allows xlarge or smaller, those nodes fall back to standard pulls and you will see bimodal pull times across the fleet. Constrain instance sizes or accept the inconsistency knowingly.

**Storage** Once downloads are parallel, disk writes become the limit. Prefer instance families with NVMe instance store (c5d, m5d, r5d, m6id, and similar) for Spark nodes; you likely want local NVMe for shuffle anyway. Where NVMe is not available, the gp3 throughput and IOPS in the config above are not optional. AWS recommends at least 600 MiB/s, with 1000 MiB/s and 16k IOPS giving better results.

**There's no universal setting** `max_concurrent_unpacks_per_image` beyond your count of non-trivial layers buys nothing. The EMR 7.12.0 base image has roughly a dozen meaningful layers out of 25, so 12 is a reasonable ceiling for it. Check your own image with `docker manifest inspect --verbose`.

**One layer can't be split** Decompression of a single layer is one stream. A 1.2 GB layer's unpack is CPU and disk bound and cannot be parallelized further. If you control the Dockerfile, splitting one giant layer into several medium ones helps both download and unpack.

## Should you enable lazy loading?

No, not for Spark. Lazy loading (SOCI's original mode) mounts the image through a FUSE filesystem and fetches file ranges from the registry on demand, so a container can start before the whole image is local. It does not eliminate download time; it moves it from pod startup into task runtime. A Spark JVM reads nearly its entire classpath at startup, so the working set is effectively the whole image. You would pay the same download cost spread across task execution, plus FUSE overhead, a runtime dependency on the registry, and the operational cost of building SOCI index artifacts for every image you ship.

The same reasoning applies to other JVM-based engines. Flink and Trino also load large classpaths at startup, as do batch and compute workloads in general, whose entrypoint touches most of the image. Lazy loading is designed for services whose entrypoint touches a small fraction of the image. Batch compute is the opposite profile. Use parallel pull mode.

## Verifying it works

On a fresh node, confirm the feature is actually active before you trust any pull timings:

```bash
# Parallel pull activity in the snapshotter logs
journalctl -u soci-snapshotter | grep -i parallel

# On NVMe instances, containerd state should sit on the RAID0 mount
df -h /var/lib/containerd

# Pull duration from the pod event
kubectl describe pod <pod> | grep -A1 Pulled
```

The most common way to get misleading results is to test on an instance below the size threshold, where the feature gate silently no-ops and pull times look identical to baseline.

## Beyond SOCI

Parallel pull attacks the pull. These attack the problem around it, roughly in order of impact:

**Keep the image lean, but cache-friendly.** Everything baked into the image is pulled once per node and shared by every pod there, and SOCI makes that pull cheap, so the goal is not to move jars out reflexively but to avoid bloat you do not need. Drop optional dependencies you never load. For artifacts that change on every deploy, chiefly your application jar and Python code, consider shipping them from S3 so a code change does not force an image rebuild and a fleet-wide re-pull. Weigh that against the tradeoff in [Loading Spark dependencies from S3](#loading-spark-dependencies-from-s3): S3 dependencies are fetched per executor and cannot use the node image cache.

**Extend node lifetime.** Review Karpenter consolidation and `expireAfter` settings. Longer lived nodes mean more cache hits and fewer cold pulls. If nodes churn every few minutes, pull time dominates regardless of how fast the pull is.

**Watch baseline network bandwidth.** Many instance types publish a burst bandwidth well above the baseline they sustain. At parallel pull speeds a smaller instance can saturate its link and, once ENA burst credits deplete, drop to baseline mid-pull. Size against the instance type's documented baseline bandwidth, not the burst headline.

**Pre-baked EBS snapshots** with the image already cached, referenced in `blockDeviceMappings`, take pulls to near zero. The trade is a snapshot lifecycle per image release. Worth it only when the image changes rarely.

Keep ECR in the same region as the cluster with a VPC endpoint. This is table stakes, but it still gets missed.

## Loading Spark dependencies from S3

Keeping the base image lean helps every cold pull, and one lever is to fetch some dependencies from S3 at submit time instead of baking them in. Spark's `--jars`, `--py-files`, and `--files` options accept any Hadoop-supported URI scheme, including `s3a://`. The driver and every executor download the referenced objects at startup and add jars to the classpath. The job's own artifact (the main jar or `.py` file) can live on S3 too.

:::warning This trades the node cache for image size

Anything baked into the image is pulled once per node and shared by every pod on it. With a per-executor S3A fetch (Pattern A below), each executor pulls its jars independently with no node-level dedup, which can bite when many executors share a node. A node-level mount (Pattern B below) restores that sharing. For large, stable, widely-shared dependencies such as connectors and common libraries, baking them in and letting SOCI pull them once is often simplest. Reserve S3 for jars that change often enough that rebuilding and re-pushing the image on every change would stall your CI/CD cycle, chiefly the application jar and Python code.

:::

:::warning The one thing you must keep in the image

The S3A filesystem client (`hadoop-aws` plus a matching AWS SDK, or EMRFS on EMR on EKS images) has to already be on the classpath, because Spark needs it to read S3 in the first place. You cannot bootstrap the S3 connector from S3. EMR on EKS base images include this; the plain `apache/spark` image does not, so add it there. Everything above the filesystem client is fair game to externalize. Pattern B is the exception: because Mountpoint exposes the bucket as a plain filesystem, even the S3A client jars can live on the mount instead of in the image.

:::

Give the pods (for S3A) or the nodes (for Mountpoint) an IAM role with `s3:GetObject` on the bucket: IRSA or EKS Pod Identity for pods, the node instance profile for the host mount.

Two patterns show up in production, and the right one depends on how many jars you have and how often they change.

### Pattern A: S3A direct fetch (few jars, changed often)

Best when a job needs one main jar, maybe with a couple of extras, and that jar changes on every deploy. Point `mainApplicationFile` and any extra `jars` at `s3a://`. The driver reads them straight from S3, with no mount, sidecar, or initContainer.

#### With `spark-submit`

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

#### With the Spark Operator (`SparkApplication`)

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

:::tip Real-world: tuning S3A for large executor counts

With a single, frequently-updated application jar fetched over S3A and a large number of executors (100 or more), the executors fetch that jar from the driver's file server as they come up. When they all launch at once, the burst can overwhelm the driver and cause fetch failures. Stagger executor allocation so the launches spread out:

```yaml
sparkConf:
  spark.kubernetes.allocation.batch.size: "50"
  spark.kubernetes.allocation.batch.delay: "5s"
```

This smooths the startup burst, not steady-state throughput, so total job time changes only marginally even at a few seconds of delay. Pairing it with the rarely-changed jars baked into the image, so only the hot jar comes from S3, is a proven setup for single-jar-per-job workloads.

:::

### Pattern B: Mountpoint for Amazon S3, node-level mount (many, independently updated jars)

Best when jobs pull 10 to 20 additional jars that different teams update on their own cadence, and rebuilding the image for every change is not worth it. Mount the bucket once per node with [Mountpoint for Amazon S3](https://github.com/awslabs/mountpoint-s3), then reference the jars as local paths. Because the mount lives at the node (host) level, every pod on the node reads the same files and Mountpoint's cache avoids re-fetching, which brings back the node-level sharing that a per-executor S3A fetch gives up.

Mount at node bring-up, from `userData` for dynamic Karpenter nodes, or from a DaemonSet for static node groups (easier to reconfigure later):

```bash
# userData or DaemonSet init. x86_64 shown; use the arm64 RPM on Graviton.
wget https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm
yum install -y ./mount-s3.rpm
mkdir -p /mnt/s3
mount-s3 --allow-other --cache /tmp <your-bucket> /mnt/s3
```

Then reference the mounted jars from the `SparkApplication` through a hostPath volume. `mountPropagation: HostToContainer` ensures the pod sees the mount even if the node remounts it:

```yaml
spec:
  mainApplicationFile: "local:///mnt/s3/jars/pyspark-taxi-trip.py"
  deps:
    jars:
      - "local:///mnt/s3/jars/hadoop-aws-3.3.1.jar"
      - "local:///mnt/s3/jars/aws-java-sdk-bundle-1.12.647.jar"
  sparkConf:
    "spark.driver.extraClassPath": "/mnt/s3/jars/*"
    "spark.executor.extraClassPath": "/mnt/s3/jars/*"
  volumes:
    - name: s3-jars
      hostPath:
        path: /mnt/s3/jars
        type: Directory
  driver:
    volumeMounts:
      - name: s3-jars
        mountPath: /mnt/s3/jars
        mountPropagation: HostToContainer
  executor:
    volumeMounts:
      - name: s3-jars
        mountPath: /mnt/s3/jars
        mountPropagation: HostToContainer
```

Avoid the S3 Mountpoint CSI driver mounted per pod for large Spark fleets. It adds a PV, a PVC, and a mount call per pod, which loads the Kubernetes API and S3 as you scale out. The node-level mount above serves every pod on the node from a single mount.

### Pulling from Maven instead

If a dependency is published to a Maven repository, `spark.jars.packages` (or `--packages`) resolves it and its transitive jars at startup, with no image bytes at all.

```bash
--packages org.apache.spark:spark-sql-kafka-0-10_2.12:3.5.0
```

The cost: every driver and executor runs Ivy resolution at startup and reaches out to a Maven repository, which adds latency and a network dependency at exactly the moment you are trying to start fast. For a large scale-out, pre-stage the resolved jars in S3 and use `--jars s3a://...` instead. Reserve `--packages` for iteration and low-fan-out jobs. If you do use it, point `spark.jars.ivy` at a writable path (for example `/tmp/.ivy2`) and consider an internal mirror.
