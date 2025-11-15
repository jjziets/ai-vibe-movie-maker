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
  mkdir -p "${DATA_DIR}" "${OUTPUT_DIR}" "${COMFY_HOME}/models"
  chown -R "${COMFY_USER}:${COMFY_USER}" "${DATA_DIR}" "${OUTPUT_DIR}" "${COMFY_HOME}" "${WRAPPER_HOME}"
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
    python main.py --listen "${COMFYUI_HOST}" --port "${COMFYUI_PORT}" --enable-cors-headers
}

shutdown() {
  echo "[init] Caught signal, shutting down..."
  [[ -n "${WRAPPER_PID:-}" ]] && kill "${WRAPPER_PID}" >/dev/null 2>&1 || true
}
trap shutdown SIGINT SIGTERM

prepare_fs
download_framepack_bundle
start_wrapper
start_comfyui

