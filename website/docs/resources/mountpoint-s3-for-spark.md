---
sidebar_position: 3
sidebar_label: Mounpoint-S3 for Spark Workloads
---


# Mountpoint-S3 for Spark Workloads

In this doc, we'll explore different approaches to using Mountpoint-S3 for data and AI/ML workloads on EKS. Specifically, we'll focus on loading external JARs located in S3 to Spark jobs and storing/caching model weights for inference. We'll discuss two main approaches for deploying Mountpoint-S3: using the EKS Managed Addon CSI driver with Persistent Volumes (PV) and Persistent Volume Claims (PVC), and deploying Mountpoint-S3 on the host using either USERDATA or a DaemonSet. We'll also delve into the pros and cons of each approach.


## 1. Loading External JARs Located in S3 to Spark Jobs Using Mountpoint-S3

### Problem Statement 

When working iwith SPark Applications jobs managed by the SparkOperator, handling multiple dependancy JAR files can become a hassle. Traditionally, these JAR files are included in the container image, which leads to several issues:

* Increased Build Time: Downloading and adding JAR files during the build process inflates the build time of the container image.
* Larger Image size: Including JAR files increases the size of the container image, leading to longer download times ehn pulling the image to execute jobs. 
* Frequent Rebuilds: Any updates or additions to the dependency JAR files necessitates rebuilding and redeploying the container image, further increasing the operational overhead. 

### Solution & Benefits: Mounting S3 Bucket

By mounting an S3 bucket directly to host nodes, the dependent JAR files can be stores and managed externally from the image and loosely couples the JAR files from the SparkApplication jobs. Addtionally storing JARs in S3 that can be consumed by multiple pods can lead to cost savings as S3 provides a cost-effective storage solution comaped to larger container images.  S3 also offers virtually unlimited storage, making it easy to scale and manage dependancies. 

### Approach 1: Deploy Mountpoint-S3 with EKS Managed Addon CSI Driver and Use PV and PVCs to Mount the Bucket at *Pod* *Level*

For more information on this approach refer to: https://awslabs.github.io/data-on-eks/docs/resources/mountpoint-s3

#### Pros:

* **Pod-Level Control**: Fine-grained control over which pods can access the S3 bucket.
* **EKS Managed**: Simplified management using EKS Managed Addon CSI driver.

#### Cons:

* **Complexity**: Involves setting up PVs and PVCs.
* **Scalability**: Might require additional configuration for large-scale deployments.



### Approach 2:  Deploy Mountpoint-S3 on the Host Using Either USERDATA or DaemonSet and Mount the Bucket at *Node Level*

Mounting a S3 Bucket at a Node level can streamline the management of dependancy JAR files for SparkApplications by  reducing build times and speeding up deployment, 

#### Approach 2.1: Deploying Using USERDATA with Karpenter or Managed Node Groups

This approach is best for new clusters or where auto-scaling is customized to run workloads as the user-data script is run when a Node is initialized. Using the below script, the Node can be updated to have the S3 bucket mounted upon initialization in the EKS cluster that hosts the pods. The below script outlines downloading, installing, and running the Mountpoint S3 Package. There are a couple of arguments that set for this application that can be altered depending on the use case. More information about this arguments can be found here: https://github.com/awslabs/mountpoint-s3/blob/main/doc/CONFIGURATION.md#caching-configuration

* metadata-ttl: this is set to indefinite because the jar files are meant to be used as read only and will not change. 
* allow-others: this is set so that the node can have access to the mounted volume when using SSM
* cache: this is set to enable caching and limit the S3 API calls that need to be made by storing the files in cache for consecutive re-reads. 


When autoscaling with Karpenter this method allows for more flexability and performance. For example when configuring Karpenter in the terraform code, the user data for different types of Nodes can be unique with different buckets depending on the workload so when Pods are scheduled and need a certain set of dependancies, Taints and Tolerations will allow Karpentar to allocate the specific instance type with the unique user data to ensure the correct bucket with the dependent files is mounted on the Node so that Pods can access is. 

#### Deployment Code:

```
bash
Copy code
#!/bin/bash
yum update -y
yum install -y wget
wget https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm
yum install -y mount-s3.rpm mkdir -p /mnt/s3
/opt/aws/mountpoint-s3/bin/mount-s3 --metadata-ttl indefinite --allow-other --cache /tmp <S3_BUCKET_NAME> /mnt/s3
```

#### Pros:

* **Automation**: Seamless deployment using node startup scripts.
* **Scalability**: Scales automatically with Karpenter or managed node groups.

#### Cons:

* **Node-Level Control**: All pods on the node can access the mounted S3 bucket, which might not be desirable.
* **Maintenance**: Requires updating the USERDATA script for changes.

### Approach 2.2: Deploying Using DaemonSet for Static Nodes

This approach is best for existing clusters. This approach is made up of 2 resources, a ConfigMap with a script that maintains the S3 Mount Point package onto the Node and a DaemonSet that runs a Pod on every Node in the cluster which will execute the script on the Node.  

The ConfigMap script will run a loop to check the mountPoint every 60 seconds and remount it if there are any issues. There are multiple environment variables that can be altered for the mount location, cache location, S3 bucket name, log file location, and the URL of the package installation and the location of the of the installed package. these variables can be left as default as only the S3 bucket name is required to run. 

The DaemonSet pods will copy the script onto the Node, alter the permissions to allow execuation, and then finally run the script. The pod requires the securityContext to be privileged, hostPID, hostIPC, and hostNetwork have to be set to true. The pod installs util-linux in order to have access to nsenter, which allows the pod execute the script in the Node space which allows the S3 Bucket to be mounted on to the Node and not the pod. 

Deployment Code:

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: s3-mount-script
  namespace: spark-team-a
data:
  monitor_s3_mount.sh: |
    #!/bin/bash

    set -e  # Exit immediately if a command exits with a non-zero status

    # ENVIRONMENT VARIABLES
    LOG_FILE="/var/log/s3-mount.log"
    S3_BUCKET_NAME="<S3_BUCKET_NAME>"  # Replace with your S3 bucket name
    MOUNT_POINT="/mnt/s3"
    CACHE_DIR="/tmp"
    MOUNT_S3_BIN="/usr/bin/mount-s3"
    MOUNT_S3_URL="https://s3.amazonaws.com/mountpoint-s3-release/latest/x86_64/mount-s3.rpm"  

    # Function to install mount-s3
    install_mount_s3() {
      echo "$(date): Installing mount-s3" | tee -a $LOG_FILE
      yum update -y | tee -a $LOG_FILE
      yum install -y wget util-linux | tee -a $LOG_FILE
      wget $MOUNT_S3_URL -O /tmp/mount-s3.rpm | tee -a $LOG_FILE
      yum install -y /tmp/mount-s3.rpm | tee -a $LOG_FILE
    }

    # Function to mount S3 bucket
    mount_s3_bucket() {
      echo "$(date): Mounting S3 bucket: $S3_BUCKET_NAME to $MOUNT_POINT" | tee -a $LOG_FILE
      $MOUNT_S3_BIN --metadata-ttl indefinite --allow-other --cache $CACHE_DIR $S3_BUCKET_NAME $MOUNT_POINT | tee -a $LOG_FILE
      if [ $? -ne 0 ]; then
        echo "$(date): Failed to mount S3 bucket: $S3_BUCKET_NAME" | tee -a $LOG_FILE
        exit 1
      fi
    }

    # Ensure the mount point directory exists
    ensure_mount_point() {
      if [ ! -d $MOUNT_POINT ]; then
        echo "$(date): Creating mount point directory: $MOUNT_POINT" | tee -a $LOG_FILE
        mkdir -p $MOUNT_POINT
      fi
    }

    # Install mount-s3
    install_mount_s3

    # Continuous monitoring and remounting loop
    while true; do
      echo "$(date): Checking if S3 bucket is mounted" | tee -a $LOG_FILE
      ensure_mount_point
      if mount | grep $MOUNT_POINT > /dev/null; then
        echo "$(date): S3 bucket is already mounted" | tee -a $LOG_FILE
        if ! ls $MOUNT_POINT > /dev/null 2>&1; then
          echo "$(date): Transport endpoint is not connected, remounting S3 bucket" | tee -a $LOG_FILE
          fusermount -u $MOUNT_POINT || echo "$(date): Failed to unmount S3 bucket" | tee -a $LOG_FILE
          rm -rf $MOUNT_POINT || echo "$(date): Failed to remove mount point directory" | tee -a $LOG_FILE
          ensure_mount_point
          mount_s3_bucket
        fi
      else
        echo "$(date): S3 bucket is not mounted, mounting now" | tee -a $LOG_FILE
        mount_s3_bucket
      fi
      sleep 60  # Check every 60 seconds
    done


---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: s3-mount-daemonset
  namespace: spark-team-a
spec:
  selector:
    matchLabels:
      name: s3-mount-daemonset
  template:
    metadata:
      labels:
        name: s3-mount-daemonset
    spec:
      hostPID: true
      hostIPC: true
      hostNetwork: true
      volumes:
      - name: script
        configMap:
          name: s3-mount-script
      - name: host-root
        hostPath:
          path: /
          type: Directory
      restartPolicy: Always
      containers:
      - name: s3-mount
        image: amazonlinux:2
        volumeMounts:
        - name: script
          mountPath: /config
        - name: host-root
          mountPath: /host
          mountPropagation: Bidirectional
        securityContext:
          privileged: true
        command: 
        - /bin/bash
        - -c
        - |
          set -e
          echo "Starting s3-mount"
          yum install -y util-linux
          echo "Copying script to /usr/bin"
          cp /config/monitor_s3_mount.sh /host/usr/bin/monitor_s3_mount.sh
          chmod +x /host/usr/bin/monitor_s3_mount.sh
          echo "Verifying the copied script"
          ls -lha /host/usr/bin/monitor_s3_mount.sh
          echo "Running the script in Host space"
          nsenter --target 1 --mount --uts --ipc --net --pid ./usr/bin/monitor_s3_mount.sh
          echo "Done"
```

#### Pros:

* **Static Node Support**: Suitable for static node environments.
* **Centralized Management**: Easy to manage and deploy across all nodes.

#### Cons:

* **Resource Utilization**: Each node runs a separate container, increasing resource usage.
* **Complexity**: Slightly more complex to set up compared to user data scripts.





* * *

## 2. Mountpoint-S3 for Storing and Caching Model Weights for Inference

Using Mountpoint-S3 to store and cache model weights can significantly enhance the performance of AI/ML workloads by reducing the latency of accessing large model files stored in S3.

### Example Deployment Code:

To-Do


## Conclusion

Mountpoint-S3 offers a versatile and powerful way to integrate S3 storage with EKS for data and AI/ML workloads. Whether you choose to deploy it at the pod level using PVs and PVCs, or at the node level using user data scripts or DaemonSets, each approach has its own set of advantages and trade-offs. By understanding these options, you can make informed decisions to optimize your data and AI/ML workflows on EKS.

