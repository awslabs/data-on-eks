#!/usr/bin/env bash
set -ex

java -jar ./jars/ivy-2.5.1.jar -dependency $@ -cache /tmp/.ivy -retrieve "./jars/[artifact]-[revision](-[classifier]).[ext]" -types jar -confs default