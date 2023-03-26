#!/bin/bash
set -o errexit
set -o pipefail

# Get user inputs 
read -p "Which Autoscaling do you want to use? Type [K] for Karpenter or [C] for ClusterAutoscaler: " choose_autoscaler

# Check user input for autoscaler
if [[ "$choose_autoscaler" =~ ^[Kk]$ ]]; then
  echo "Switching to Karpenter examples. We have examples for different storage types (NVMe SSD, EBS, FSX for Lustre) and different instance types (compute-optimized, memory-optimized, graviton-optimized)"
  read -p "Which storage type do you want to use in your Spark job? Type [N] for NVMe, [E] for EBS, [F] for FSx for Lustre: " choose_karpenter_storage

  case $choose_karpenter_storage in
    "N")echo "Switching to NVMe storage type example"
        read -p "Which instance type do you want to use in your Spark job? Type [C] for Compute, [R]for Memory, [G] for Graviton: " choose_karpenter_compute
        case $choose_karpenter_compute in
            "C") echo "You chose to run job using Karpenter using NVMe on $choose_karpenter_compute instance type" 
                WORK_DIR="nvme-ssd/karpenter-compute-provisioner/"
                cd $WORK_DIR            
                ./execute_emr_eks_job.sh
                ;;
            "R") echo "You chose to run job using Karpenter using NVMe on $choose_karpenter_compute instance type" 
                WORK_DIR="nvme-ssd/karpenter-memory-provisioner/"
                cd $WORK_DIR
                ./execute_emr_eks_job.sh
                ;;      
            "G") echo "You chose to run job using Karpenter using NVMe on $choose_karpenter_compute instance type" 
                WORK_DIR="nvme-ssd/karpenter-graviton-memory-provisioner/"
                cd $WORK_DIR
                ./execute_emr_eks_job.sh
                ;;
        esac
        ;;
    "E")echo "Switching to EBS storage type example"
        read -p "Which instance type do you want to use in your Spark job? Type [C] for Compute, [R]for Memory, [G] for Graviton: " choose_karpenter_compute
        case $choose_karpenter_compute in
            "C") echo "You chose to run job using Karpenter using EBS on $choose_karpenter_compute instance type" 
                WORK_DIR="ebs-pvc/karpenter-compute-provisioner-ebs/"
                cd $WORK_DIR
                ./execute_emr_eks_job.sh
                ;;
            "R") echo "You chose to run job using Karpenter using EBS on $choose_karpenter_compute instance type" 
                echo "This example is in Work-in-progress. Please see compute provisioner example and modify if possible"
                # cd "ebs-pvc/karpenter-memory-provisioner/"
                # ./execute_emr_eks_job.sh
                ;;      
            "G") echo "You chose to run job using Karpenter using EBS on $choose_karpenter_compute instance type" 
                echo "This example is in Work-in-progress. Please see compute provisioner example and modify if possible"                
                # cd "ebs-pvc/karpenter-graviton-memory-provisioner/"
                # ./execute_emr_eks_job.sh
                ;;
        esac
        ;;        
    "F")echo "Switching to FSx for Lustre storage type example"
        read -p "Which instance type do you want to use in your Spark job? Type [C] for Compute, [R]for Memory, [G] for Graviton: " choose_karpenter_compute
        case $choose_karpenter_compute in
            "C") echo "You chose to run job using Karpenter using FSx for Lustre on $choose_karpenter_compute instance type" 
                cd "fsx-for-lustre/fsx-static-pvc-shuffle-storage/"
                ./fsx-static-spark.sh
                ;;
            "R") echo "You chose to run job using Karpenter using FSx for Lustre on $choose_karpenter_compute instance type" 
                echo "This example is in Work-in-progress. Please see compute provisioner example and modify if possible"
                # cd "fsx-for-lustre/fsx-static-pvc-shuffle-storage/"
                # ./execute_emr_eks_job.sh
                ;;      
            "G") echo "You chose to run job using Karpenter using FSx for Lustre on $choose_karpenter_compute instance type" 
                echo "This example is in Work-in-progress. Please see compute provisioner example and modify if possible"                
                # cd "fsx-for-lustre/fsx-static-pvc-shuffle-storage/"
                # ./execute_emr_eks_job.sh
                ;;
        esac
        ;;        
    *) echo "Invalid choice"
        ;;
    esac

elif [[ "$choose_autoscaler" =~ ^[Cc]$ ]]; then
  echo "Switching to Cluster Autoscaler examples. We have examples for different storage types (NVMe SSD, EBS, FSX for Lustre) and different instance types (compute-optimized, memory-optimized, graviton-optimized)"
  read -p "Which storage type do you want to use in your Spark job? Type [N] for NVMe, [E] for EBS, [F] for FSx for Lustre: " choose_ca_storage
  case $choose_ca_storage in
    "N")echo "Switching to NVMe storage type example"
        read -p "Which instance type do you want to use in your Spark job? Type [C] for Compute, [R]for Memory, [G] for Graviton: " choose_ca_compute
        case $choose_ca_compute in
            "C") echo "You chose to run job using ClusterAutoscaler using NVMe on $choose_ca_compute instance type" 
                WORK_DIR="cluster-autoscaler/nvme-ssd/cluster-autoscaler-compute-optimized/"
                cd $WORK_DIR
                ./execute_emr_eks_job.sh
                ;;
            "R") echo "You chose to run job using ClusterAutoscaler using NVMe on $choose_ca_compute instance type" 
                echo "This example is in Work-in-progress. Please see compute provisioner example and modify if possible"               
                # cd "cluster-autoscaler/nvme-ssd/cluster-autoscaler-memory-optimized/"
                # ./execute_emr_eks_job.sh
                ;;      
            "G") echo "You chose to run job using ClusterAutoscaler using NVMe on $choose_ca_compute instance type" 
                echo "This example is in Work-in-progress. Please see compute provisioner example and modify if possible"               
                # cd "cluster-autoscaler/nvme-ssd/cluster-autoscaler-graviton-memory-optimized/"
                # ./execute_emr_eks_job.sh
                ;;
        esac
        ;;
    "E")echo "Switching to EBS storage type example"
        read -p "Which instance type do you want to use in your Spark job? Type [C] for Compute, [R]for Memory, [G] for Graviton: " choose_ca_compute
        case $choose_ca_compute in
            "C") echo "You chose to run job using ClusterAutoscaler using EBS on $choose_ca_compute instance type" 
                WORK_DIR="cluster-autoscaler/ebs-pvc/cluster-autoscaler-compute-optimized/"
                cd $WORK_DIR
                ./execute_emr_eks_job.sh
                ;;
            "R") echo "You chose to run job using ClusterAutoscaler using EBS on $choose_ca_compute instance type" 
                echo "This example is in Work-in-progress. Please see compute provisioner example and modify if possible"               
                # cd "cluster-autoscaler/ebs-pvc/cluster-autoscaler-memory-optimized/"
                # ./execute_emr_eks_job.sh
                ;;      
            "G") echo "You chose to run job using ClusterAutoscaler using EBS on $choose_ca_compute instance type" 
                echo "This example is in Work-in-progress. Please see compute provisioner example and modify if possible"               
                # cd "cluster-autoscaler/ebs-pvc/cluster-autoscaler-graviton-memory-optimized/"
                # ./execute_emr_eks_job.sh
                ;;
        esac
        ;;
    "F")echo "Switching to FSx for Lustre storage type example"
        read -p "Which instance type do you want to use in your Spark job? Type [C] for Compute, [R]for Memory, [G] for Graviton: " choose_ca_compute
        case $choose_ca_compute in
            "C") echo "You chose to run job using ClusterAutoscaler using FSx for Lustre on $choose_ca_compute instance type" 
                echo "This example is in Work-in-progress. Please see EBS Compute example and modify if possible"                 
                # cd "cluster-autoscaler/fsx-for-lustre/cluster-autoscaler-compute-optimized/"
                # ./execute_emr_eks_job.sh
                ;;
            "R") echo "You chose to run job using ClusterAutoscaler using FSx for Lustre on $choose_ca_compute instance type" 
                echo "This example is in Work-in-progress. Please see EBS Compute example and modify if possible"               
                # cd "cluster-autoscaler/fsx-for-lustre/cluster-autoscaler-memory-optimized/"
                # ./execute_emr_eks_job.sh
                ;;      
            "G") echo "You chose to run job using ClusterAutoscaler using FSx for Lustre on $choose_ca_compute instance type" 
                echo "This example is in Work-in-progress. Please see EBS Compute example and modify if possible"               
                # cd "cluster-autoscaler/fsx-for-lustre/cluster-autoscaler-graviton-memory-optimized/"
                # ./execute_emr_eks_job.sh
                ;;
        esac
        ;;
    *) echo "Invalid choice"
        ;;
    esac
else
    echo "Invalid choice"
fi