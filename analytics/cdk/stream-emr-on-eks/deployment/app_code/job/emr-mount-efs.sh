#!/bin/bash
set -ex

if [[ -z "$1" || -z "$2" ]]
  then
    echo "Missing mandatory arguments: File system ID, region"
    exit 1
fi

# get file system id from input argument
fs_id=$1

# get region from input argument
region_id=$2

# verify file system is ready
times=0
echo
while [ 5 -gt $times ] && ! aws efs describe-file-systems --file-system-id $fs_id --region $region_id --no-paginate | grep -Po "available"
do
  sleep 5
  times=$(( $times + 1 ))
  echo Attempt $times at verifying efs $fs_id is available...
done

# verify mount target is ready
times=0
echo
while [ 5 -gt $times ] && ! aws efs describe-mount-targets --file-system-id $fs_id --region $region_id --no-paginate | grep -Po "available"
do
  sleep 5
  times=$(( $times + 1 ))
  echo Attempt $times at verifying efs $fs_id mount target is available...
done

# create local path to mount efs
sudo mkdir -p /efs

# mount efs
until sudo mount -t nfs4 \
           -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 \
           $fs_id.efs.$region_id.amazonaws.com:/ \
           /efs; do echo "Shared filesystem no ready yet..." ; sleep 5; done

cd /efs

# give hadoop user permission to efs directory
sudo chown -R hadoop:hadoop .

if grep  $fs_id /proc/mounts; then
  echo "File system is mounted successfully."
else
  echo "File system mounting is unsuccessful."
  exit 1
fi
