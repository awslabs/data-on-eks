#!/bin/bash

export MODEL_S3_URL="s3://kaena-nn-models/llama3.1/405b-bf16"
mkdir /awscli \
    && wget https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -O /awscli/awscliv2.zip  \
    && unzip /awscli/awscliv2.zip -d /awscli/ \
    && /awscli/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli --update \
    && rm -rf /awscli


# Model is available under S3 bucket 

export MODEL_S3_URL="s3://llama-model-405b-weights/405b-bf16/"

aws configure set default.s3.preferred_transfer_client crt
aws configure set default.s3.target_bandwidth 100Gb/s
aws configure set default.s3.max_concurrent_requests 20

mkdir -p /mnt/k8s-disks/0/checkpoints/llama-3.1-405b-instruct/
/usr/local/bin/aws s3 sync $MODEL_S3_URL /mnt/k8s-disks/0/checkpoints/llama-3.1-405b-instruct/

##################################################################################
# It took >5 mins mins to copy the Llama3_405 model weights(764G) from S3 bucket to local SSD using AWS S3 SYNC CRT
##################################################################################

#root@ip-100-64-31-64 0]# ./model-downloader-script.sh
# download: s3://llama-model-405b-weights/405b-bf16/LICENSE to checkpoints/llama-3.1-405b-instruct/LICENSE
# download: s3://llama-model-405b-weights/405b-bf16/README.md to checkpoints/llama-3.1-405b-instruct/README.md
# download: s3://llama-model-405b-weights/405b-bf16/USE_POLICY.md to checkpoints/llama-3.1-405b-instruct/USE_POLICY.md
# download: s3://llama-model-405b-weights/405b-bf16/config.json to checkpoints/llama-3.1-405b-instruct/config.json
# download: s3://llama-model-405b-weights/405b-bf16/generation_config.json to checkpoints/llama-3.1-405b-instruct/generation_config.json
# download: s3://llama-model-405b-weights/405b-bf16/model-00002-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00002-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00005-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00005-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00008-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00008-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00029-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00029-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00026-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00026-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00044-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00044-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00038-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00038-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00020-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00020-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00011-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00011-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00041-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00041-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00050-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00050-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00014-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00014-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00023-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00023-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00035-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00035-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00065-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00065-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00017-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00017-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00056-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00056-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00059-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00059-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00062-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00062-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00047-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00047-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00032-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00032-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00053-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00053-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00068-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00068-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00074-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00074-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00071-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00071-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00077-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00077-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00003-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00003-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00021-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00021-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00063-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00063-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00031-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00031-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00060-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00060-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00042-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00042-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00012-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00012-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00004-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00004-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00037-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00037-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00061-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00061-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00015-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00015-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00007-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00007-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00028-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00028-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00066-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00066-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00051-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00051-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00033-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00033-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00006-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00006-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00055-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00055-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00030-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00030-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00043-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00043-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00036-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00036-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00016-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00016-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00040-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00040-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00013-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00013-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00019-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00019-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00022-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00022-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00009-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00009-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00052-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00052-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00025-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00025-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00045-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00045-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00048-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00048-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00039-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00039-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00058-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00058-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00080-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00080-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00067-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00067-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00069-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00069-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00001-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00001-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00034-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00034-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00057-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00057-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00027-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00027-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00018-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00018-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00049-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00049-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00064-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00064-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00054-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00054-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00046-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00046-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00073-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00073-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00010-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00010-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00024-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00024-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00075-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00075-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00070-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00070-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00076-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00076-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00072-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00072-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00078-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00078-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00079-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00079-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00083-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00083-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00081-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00081-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00086-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00086-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00089-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00089-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00092-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00092-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00082-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00082-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00104-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00104-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00101-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00101-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00098-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00098-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00110-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00110-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00095-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00095-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00113-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00113-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00085-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00085-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00084-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00084-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00107-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00107-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00116-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00116-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00087-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00087-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00119-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00119-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00122-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00122-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00094-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00094-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00109-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00109-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00093-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00093-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00134-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00134-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00125-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00125-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00112-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00112-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00099-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00099-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00088-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00088-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00090-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00090-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00091-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00091-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00131-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00131-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00096-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00096-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model.safetensors.index.json to checkpoints/llama-3.1-405b-instruct/model.safetensors.index.json
# download: s3://llama-model-405b-weights/405b-bf16/model-00097-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00097-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00105-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00105-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00137-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00137-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00140-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00140-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00103-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00103-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00146-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00146-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00100-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00100-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00102-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00102-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00108-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00108-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00114-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00114-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00143-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00143-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00111-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00111-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00115-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00115-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00152-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00152-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00118-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00118-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00121-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00121-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00120-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00120-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00106-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00106-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00123-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00123-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00155-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00155-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00127-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00127-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00129-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00129-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00124-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00124-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00128-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00128-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00133-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00133-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00126-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00126-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00132-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00132-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00130-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00130-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00135-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00135-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00136-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00136-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00138-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00138-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00139-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00139-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00117-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00117-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00149-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00149-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00142-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00142-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00144-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00144-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00141-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00141-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00147-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00147-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00148-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00148-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00150-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00150-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00154-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00154-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00151-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00151-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00145-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00145-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00153-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00153-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00156-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00156-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00157-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00157-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00159-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00159-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00160-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00160-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00158-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00158-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00164-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00164-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00161-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00161-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00163-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00163-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00165-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00165-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00167-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00167-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00168-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00168-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00166-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00166-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00170-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00170-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00169-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00169-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00171-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00171-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00173-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00173-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00174-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00174-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00176-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00176-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00172-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00172-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00175-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00175-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00177-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00177-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00179-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00179-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00182-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00182-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00178-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00178-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00181-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00181-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00162-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00162-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00180-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00180-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00183-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00183-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00185-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00185-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00184-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00184-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00187-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00187-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00186-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00186-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00191-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00191-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00190-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00190-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00189-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00189-of-00191.safetensors
# download: s3://llama-model-405b-weights/405b-bf16/model-00188-of-00191.safetensors to checkpoints/llama-3.1-405b-instruct/model-00188-of-00191.safetensors

# [root@ip-100-64-31-64 llama-3.1-405b-instruct]# du -h
# 764G 