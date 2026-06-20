#!/usr/bin/env bash
set -euo pipefail

export CUDA_HOME=/usr/local/cuda
export PATH=/opt/conda/envs/slahmr/bin:/opt/conda/bin:$PATH
export CONDA_DEFAULT_ENV=slahmr
export PYTHONUNBUFFERED=1
export FORCE_CUDA=1

WORK_DIR="/workspace/slahmr"
STATE_DIR="/var/lib/slahmr"
STAMP_FILE="${STATE_DIR}/.deps_installed"

VITPOSE_DIR="${WORK_DIR}/third-party/ViTPose"
DROID_SLAM_DIR="${WORK_DIR}/third-party/DROID-SLAM"

# -------------------------------------------------------
# Logging helpers
# -------------------------------------------------------
log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
err()  { echo "[ERROR] $*" >&2; }

# -------------------------------------------------------
# Abort if a required directory is missing
# -------------------------------------------------------
require_dir() {
  local dir="$1"
  local hint="$2"
  if [ ! -d "${dir}" ]; then
    err "Required directory not found: ${dir}"
    log "${hint}"
    exit 1
  fi
}

# -------------------------------------------------------
# Import / package sanity checks
# -------------------------------------------------------
python_ok() {
  python - <<'PY' >/dev/null 2>&1
import sys
sys.exit(0)
PY
}

mmpose_ok() {
  python - <<'PY' >/dev/null 2>&1
import mmpose
PY
}

vitpose_pkg_ok() {
  python -m pip show mmpose >/dev/null 2>&1
}

droid_ok() {
  python - <<'PY' >/dev/null 2>&1
import droid_backends
PY
}

# -------------------------------------------------------
# Return 0 (true) when bootstrap is needed.
# Even if STAMP_FILE exists, re-bootstrap when any import
# check fails (e.g. after 'docker compose run --rm' spins
# up a fresh container against a clean named volume).
# -------------------------------------------------------
need_bootstrap() {
  if [ ! -f "${STAMP_FILE}" ]; then
    return 0
  fi

  if ! python_ok; then
    warn "Python environment check failed."
    return 0
  fi

  if ! mmpose_ok; then
    warn "mmpose import check failed."
    return 0
  fi

  if ! vitpose_pkg_ok; then
    warn "pip metadata for mmpose is missing."
    return 0
  fi

  if ! droid_ok; then
    warn "DROID-SLAM backend import check failed."
    return 0
  fi

  return 1
}

# -------------------------------------------------------
# Install ViTPose (editable) and build DROID-SLAM.
# -------------------------------------------------------
bootstrap_dev() {
  log "Running development bootstrap..."

  log "Installing ViTPose (editable)..."
  python -m pip install -v -e "${VITPOSE_DIR}"

  log "Building DROID-SLAM..."
  cd "${DROID_SLAM_DIR}"
  python setup.py install

  cd "${WORK_DIR}"
  touch "${STAMP_FILE}"
  log "Development bootstrap completed."
}

# -------------------------------------------------------
# preflight_hmr2: ensure hmr2_data is extracted into
# the model cache before Python ever calls download_models().
#
# Priority:
#   1. Sentinel already present  -> already extracted, nothing to do.
#   2. Host-side tarball present -> copy into cache and extract.
#   3. Neither present           -> let download_models() handle the
#                                   remote download at runtime.
# -------------------------------------------------------
preflight_hmr2() {
  local cache_dir="/root/.cache/4DHumans"
  local sentinel="${cache_dir}/logs/train/multiruns/hmr2/0/model_config.yaml"
  local host_tarball="/workspace/data/models/hmr2_data.tar.gz"
  local cache_tarball="${cache_dir}/hmr2_data.tar.gz"

  mkdir -p "${cache_dir}"

  # Case 1: already fully extracted.
  if [ -f "${sentinel}" ]; then
    log "hmr2_data already extracted; skipping preflight."
    return 0
  fi

  # Case 2: host-side tarball available -- copy and extract locally.
  if [ -f "${host_tarball}" ]; then
    log "Copying host-side hmr2_data.tar.gz to cache..."
    cp "${host_tarball}" "${cache_tarball}"

    log "Extracting hmr2_data.tar.gz ..."
    tar -xf "${cache_tarball}" -C "${cache_dir}"

    if [ ! -f "${sentinel}" ]; then
      err "Extraction finished but sentinel not found: ${sentinel}"
      rm -f "${cache_tarball}"
      exit 1
    fi

    rm -f "${cache_tarball}"
    log "hmr2_data extraction complete (from host-side tarball)."
    return 0
  fi

  # Case 3: no local source -- download_models() will fetch from remote.
  log "No host-side hmr2_data.tar.gz found; download_models() will fetch from remote."
}

# -------------------------------------------------------
# Main
# -------------------------------------------------------
mkdir -p "${STATE_DIR}"

require_dir "${WORK_DIR}"       "Run on host: make init && make setup"
require_dir "${VITPOSE_DIR}"    "Host-side SLAHMR tree is incomplete. Run on host: make reinit && make setup"
require_dir "${DROID_SLAM_DIR}" "Host-side SLAHMR tree is incomplete. Run on host: make reinit && make setup"

cd "${WORK_DIR}"

preflight_hmr2

if need_bootstrap; then
  bootstrap_dev
else
  log "Dependencies already installed and importable. Skipping bootstrap."
fi

exec "$@"
