#!/usr/bin/env bash
set -euo pipefail

cd /workspace/slahmr

SRC_VIDEO="${1:-/workspace/data/inputs/sample_video.mp4}"
SEQ_NAME="${2:-$(basename "${SRC_VIDEO%.*}")}"

DATA_ROOT="${DATA_ROOT:-/workspace/data}"
DATA_SPLIT="${DATA_SPLIT:-val}"
GPU_IDS="${GPU_IDS:-0}"
FPS="${FPS:-}"
CFG_PATH="${CUSTOM_CFG:-/workspace/slahmr/slahmr/confs/data/custom.yaml}"

IMAGES_DIR="${DATA_ROOT}/images/${SEQ_NAME}"
TRACKS_DIR="${DATA_ROOT}/slahmr/track_preds/${SEQ_NAME}"
SHOTS_FILE="${DATA_ROOT}/slahmr/shot_idcs/${SEQ_NAME}.json"
CAM_DIR="${DATA_ROOT}/slahmr/cameras/${SEQ_NAME}"

mkdir -p "${IMAGES_DIR}" \
         "$(dirname "${TRACKS_DIR}")" \
         "$(dirname "${SHOTS_FILE}")" \
         "${CAM_DIR}"

if [[ ! -f "${SRC_VIDEO}" ]]; then
  echo "[ERROR] source video not found: ${SRC_VIDEO}"
  exit 1
fi

echo "[INFO] source video : ${SRC_VIDEO}"
echo "[INFO] sequence     : ${SEQ_NAME}"
echo "[INFO] data root    : ${DATA_ROOT}"
echo "[INFO] split        : ${DATA_SPLIT}"
echo "[INFO] gpus         : ${GPU_IDS}"

echo "[STEP 1] Extract frames to ${IMAGES_DIR}"
rm -f "${IMAGES_DIR}"/*.jpg
if [[ -n "${FPS}" ]]; then
  ffmpeg -y -i "${SRC_VIDEO}" -vf "fps=${FPS}" "${IMAGES_DIR}/%06d.jpg"
else
  ffmpeg -y -i "${SRC_VIDEO}" "${IMAGES_DIR}/%06d.jpg"
fi

FRAME_COUNT=$(find "${IMAGES_DIR}" -maxdepth 1 -name '*.jpg' | wc -l | tr -d ' ')
if [[ "${FRAME_COUNT}" == "0" ]]; then
  echo "[ERROR] no frames extracted to ${IMAGES_DIR}"
  exit 1
fi
END_IDX=$((FRAME_COUNT - 1))

if [[ -f "${CFG_PATH}" && ! -f "${CFG_PATH}.orig" ]]; then
  cp "${CFG_PATH}" "${CFG_PATH}.orig"
  echo "[INFO] backed up original: ${CFG_PATH}.orig"
fi

echo "[STEP 2] Write Hydra custom config"
cat > "${CFG_PATH}" <<EOCFG
type: custom
split: ${DATA_SPLIT}
video: ${SRC_VIDEO}
seq: ${SEQ_NAME}
root: ${DATA_ROOT}
use_cams: True
track_ids: "all"
shot_idx: 0
start_idx: 0
end_idx: ${END_IDX}
split_cameras: True
name: \${data.seq}-\${data.track_ids}-shot-\${data.shot_idx}
sources:
  images: \${data.root}/images/\${data.seq}
  cameras: \${data.root}/slahmr/cameras/\${data.seq}
  tracks: \${data.root}/slahmr/track_preds/\${data.seq}
  shots: \${data.root}/slahmr/shot_idcs/\${data.seq}.json
EOCFG

echo "[INFO] config written: ${CFG_PATH}"
echo "[INFO] frame count   : ${FRAME_COUNT}"

export PYTHONPATH=/workspace/slahmr/slahmr

echo "[STEP 3] Run PHALP preprocessing"
cd /workspace/slahmr/slahmr/preproc
python launch_phalp.py \
  --type custom \
  --root "${DATA_ROOT}" \
  --split "${DATA_SPLIT}" \
  --seqs "${SEQ_NAME}" \
  --gpus "${GPU_IDS}"

echo "[STEP 4] Run SLAM preprocessing"
python launch_slam.py \
  --type custom \
  --root "${DATA_ROOT}" \
  --split "${DATA_SPLIT}" \
  --seqs "${SEQ_NAME}" \
  --gpus "${GPU_IDS}"

cd /workspace/slahmr

echo "[STEP 5] Validate expected outputs"
if [[ ! -d "${TRACKS_DIR}" ]]; then
  echo "[WARN] track dir not found yet: ${TRACKS_DIR}"
fi

if [[ ! -f "${SHOTS_FILE}" ]]; then
  echo "[WARN] shots file not found yet: ${SHOTS_FILE}"
fi

if [[ ! -d "${CAM_DIR}" ]]; then
  echo "[WARN] camera dir not found: ${CAM_DIR}"
  echo "[INFO] actual files under ${DATA_ROOT}/slahmr:"
  find "${DATA_ROOT}/slahmr" -maxdepth 4 \( -type d -o -type f \) | sort | sed -n '1,200p'
fi

echo "[DONE] preprocessing completed"
echo "[INFO] frames  : ${IMAGES_DIR}"
echo "[INFO] tracks  : ${TRACKS_DIR}"
echo "[INFO] shots   : ${SHOTS_FILE}"
echo "[INFO] cameras : ${CAM_DIR}"
echo "[INFO] next    : /workspace/slahmr/scripts/run_custom_demo.sh"