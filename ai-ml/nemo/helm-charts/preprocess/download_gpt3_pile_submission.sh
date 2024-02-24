#!/bin/bash
helm install --timeout=15m --wait  download-gpt3-pile ./k8s_template
