#!/usr/bin/env bash
set -euo pipefail

export CUDA_HOME=/usr/local/cuda
export PATH=/opt/conda/envs/slahmr/bin:/opt/conda/bin:$PATH
export CONDA_DEFAULT_ENV=slahmr

if [ -d /workspace/slahmr ]; then
  cd /workspace/slahmr
else
  cd /workspace
fi

exec "$@"
