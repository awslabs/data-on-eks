#!/bin/bash

set -e

cd "$(dirname "$0")/terraform/_local"
./cleanup.sh
