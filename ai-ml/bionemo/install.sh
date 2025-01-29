#!/bin/bash
# Copy the base infrastructure into the folder
cp -r ../infrastructure/terraform/* ./terraform

cd terraform
source ./install.sh
