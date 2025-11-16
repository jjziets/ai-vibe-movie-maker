#!/usr/bin/env bash
set -euo pipefail

COMFY_USER="${COMFY_USER:-comfy}"
COMFY_HOME="${COMFY_HOME:-/opt/ComfyUI}"
WRAPPER_HOME="${WRAPPER_HOME:-/opt/framepack_wrapper}"
DATA_DIR="${COMFYUI_DATA_DIR:-/data}"
OUTPUT_DIR="${COMFYUI_OUTPUT_DIR:-/outputs}"
PUBLIC_BASE_URL="${PUBLIC_BASE_URL:-https://framepack.ai.cryptolabs.co.za}"
FRAMEPACK_BUNDLE_URL="${FRAMEPACK_BUNDLE_URL:-}"
FRAMEPACK_LICENSE_KEY="${FRAMEPACK_LICENSE_KEY:-}"
WRAPPER_PORT="${WRAPPER_PORT:-9443}"
WRAPPER_HOST="${WRAPPER_HOST:-0.0.0.0}"
COMFYUI_PORT="${COMFYUI_PORT:-9090}"
COMFYUI_HOST="${COMFYUI_HOST:-0.0.0.0}"
LOG_LEVEL="${WRAPPER_LOG_LEVEL:-info}"
FRAMEPACK_MAX_CONTEXT="${FRAMEPACK_MAX_CONTEXT:-2048}"
FRAMEPACK_TEA_CACHE="${FRAMEPACK_TEA_CACHE:-false}"
NCCL_P2P_LEVEL="${NCCL_P2P_LEVEL:-NVL}"
NCCL_ASYNC_ERROR_HANDLING="${NCCL_ASYNC_ERROR_HANDLING:-1}"
NCCL_DEBUG="${NCCL_DEBUG:-WARN}"
FRAMEPACK_PREFETCH_MODELS="${FRAMEPACK_PREFETCH_MODELS:-true}"

# Ensure wrapper is importable for both root and gosu user
export PYTHONPATH="${WRAPPER_HOME}:${PYTHONPATH:-}"

download_framepack_bundle() {
  local bundle_path="${DATA_DIR}/framepack/bundle.zip"
  local stamp="${DATA_DIR}/framepack/.bundle.stamp"

  [[ -z "${FRAMEPACK_BUNDLE_URL}" ]] && return 0

  if [[ ! -f "${stamp}" ]]; then
    echo "[init] Downloading FramePack bundle from ${FRAMEPACK_BUNDLE_URL}"
    mkdir -p "$(dirname "${bundle_path}")"
    curl -fsSL "${FRAMEPACK_BUNDLE_URL}" -o "${bundle_path}"
    unzip -oq "${bundle_path}" -d "${DATA_DIR}/framepack"
    echo "${FRAMEPACK_BUNDLE_URL}" > "${stamp}"
  fi
}

prepare_fs() {
  local hf_dir="${HF_HOME:-/opt/.cache/huggingface}"
  mkdir -p "${DATA_DIR}" "${OUTPUT_DIR}" "${COMFY_HOME}/models" "${hf_dir}"
  chown -R "${COMFY_USER}:${COMFY_USER}" \
    "${DATA_DIR}" \
    "${OUTPUT_DIR}" \
    "${COMFY_HOME}" \
    "${WRAPPER_HOME}" \
    "${hf_dir}"
}

prefetch_models() {
  if [[ "${FRAMEPACK_PREFETCH_MODELS}" != "true" ]]; then
    echo "[init] Model prefetch disabled via FRAMEPACK_PREFETCH_MODELS=${FRAMEPACK_PREFETCH_MODELS}"
    return
  fi

  local script=$(cat <<'PY'
import os
from huggingface_hub import snapshot_download

targets = [
    ("lllyasviel/FramePackI2V_HY", "/opt/ComfyUI/models/diffusers/lllyasviel/FramePackI2V_HY"),
    ("lllyasviel/FramePack_F1_I2V_HY_20250503", "/opt/ComfyUI/models/diffusers/lllyasviel/FramePack_F1_I2V_HY_20250503"),
    ("Comfy-Org/HunyuanVideo_repackaged", "/opt/ComfyUI/models/diffusers/Comfy-Org/HunyuanVideo_repackaged"),
    ("Comfy-Org/sigclip_vision_384", "/opt/ComfyUI/models/clip_vision/sigclip_vision_384"),
    ("Kijai/HunyuanVideo_comfy", "/opt/ComfyUI/models/diffusion_models/Kijai/HunyuanVideo_comfy"),
]

token = os.environ.get("HUGGING_FACE_HUB_TOKEN")

for repo_id, dest in targets:
    dest = dest.rstrip("/")
    if os.path.exists(dest) and any(os.scandir(dest)):
        print(f"[prefetch] {dest} already populated; skipping {repo_id}")
        continue
    os.makedirs(dest, exist_ok=True)
    print(f"[prefetch] Downloading {repo_id} -> {dest}")
    snapshot_download(
        repo_id=repo_id,
        local_dir=dest,
        local_dir_use_symlinks=False,
        token=token,
    )
PY
)

  echo "[init] Prefetching FramePack model weights (this may take a while)..."
  gosu "${COMFY_USER}" env HF_HOME="${HF_HOME:-/opt/.cache/huggingface}" python - <<PY
$script
PY
}

start_wrapper() {
  echo "[init] Starting FramePack wrapper on ${WRAPPER_HOST}:${WRAPPER_PORT}"
  gosu "${COMFY_USER}" \
    env \
      COMFYUI_URL="http://127.0.0.1:${COMFYUI_PORT}" \
      PUBLIC_BASE_URL="${PUBLIC_BASE_URL}" \
      FRAMEPACK_LICENSE_KEY="${FRAMEPACK_LICENSE_KEY}" \
      DATA_DIR="${DATA_DIR}" \
      OUTPUT_DIR="${OUTPUT_DIR}" \
      LOG_LEVEL="${LOG_LEVEL}" \
      WRAPPER_PORT="${WRAPPER_PORT}" \
      WRAPPER_HOST="${WRAPPER_HOST}" \
      FRAMEPACK_MAX_CONTEXT="${FRAMEPACK_MAX_CONTEXT}" \
      FRAMEPACK_TEA_CACHE="${FRAMEPACK_TEA_CACHE}" \
    python -m framepack_wrapper.app &
  WRAPPER_PID=$!
}

start_comfyui() {
  echo "[init] Starting ComfyUI on ${COMFYUI_HOST}:${COMFYUI_PORT}"
  gosu "${COMFY_USER}" \
    env \
      COMFYUI_HOST="${COMFYUI_HOST}" \
      COMFYUI_PORT="${COMFYUI_PORT}" \
      HF_HOME="${HF_HOME:-/opt/.cache/huggingface}" \
      CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}" \
      NCCL_P2P_LEVEL="${NCCL_P2P_LEVEL}" \
      NCCL_ASYNC_ERROR_HANDLING="${NCCL_ASYNC_ERROR_HANDLING}" \
      NCCL_DEBUG="${NCCL_DEBUG}" \
    python main.py --listen "${COMFYUI_HOST}" --port "${COMFYUI_PORT}" --enable-cors-header
}

shutdown() {
  echo "[init] Caught signal, shutting down..."
  [[ -n "${WRAPPER_PID:-}" ]] && kill "${WRAPPER_PID}" >/dev/null 2>&1 || true
}
trap shutdown SIGINT SIGTERM

prepare_fs
download_framepack_bundle

# Start services immediately, prefetch in background
start_wrapper
(prefetch_models &)
start_comfyui

