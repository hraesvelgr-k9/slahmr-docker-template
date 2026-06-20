#!/usr/bin/env bash
set -euo pipefail

cd /workspace/slahmr/slahmr

CUSTOM_CFG="${CUSTOM_CFG:-/workspace/slahmr/slahmr/confs/data/custom.yaml}"
RUN_VIS="${RUN_VIS:-True}"
RUN_OPT="${RUN_OPT:-True}"

export PYTHONPATH=/workspace/slahmr/slahmr

echo "[INFO] Using config: ${CUSTOM_CFG}"
python -c "import torch, detectron2, phalp; print('torch ok, cuda:', torch.cuda.is_available())"

python run_opt.py \
  data=custom \
  run_opt="${RUN_OPT}" \
  run_vis="${RUN_VIS}"

echo "[INFO] Outputs are typically written under /workspace/slahmr/outputs"