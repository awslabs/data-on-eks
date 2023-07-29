# Tensorboard container for use in the EKS/Trn1 BERT pretraining tutorial
FROM ubuntu:20.04
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y nginx python3-pip apache2-utils curl
RUN python3 -m pip install --upgrade pip && python3 -m pip install tensorboard

# TB_PASSWORD is specified during container build
ARG TB_PASSWORD=""

RUN htpasswd -c -b /etc/nginx/htpasswd admin $TB_PASSWORD
COPY assets/nginx_auth.conf /etc/nginx/sites-enabled/default
