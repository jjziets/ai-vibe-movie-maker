#!/usr/bin/env bash
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-ghcr.io/jjziets/ai-vibe-movie-maker:latest}"
GPU_SSH_HOST="${GPU_SSH_HOST:-41.193.204.66}"
GPU_SSH_PORT="${GPU_SSH_PORT:-101}"
GPU_SSH_USER="${GPU_SSH_USER:-root}"
REMOTE_DIR="${REMOTE_DIR:-/home/vast/ai-vibe-movie-maker}"
STACK_COMPOSE_FILE="${STACK_COMPOSE_FILE:-compose/docker-compose.gpu.yml}"
ENV_FILE_REMOTE="${ENV_FILE_REMOTE:-/home/vast/ai-vibe-movie-maker/comfyui.env}"

if [[ -z "${GPU_SSH_KEY:-}" ]]; then
  echo "GPU_SSH_KEY env var must contain the private key (base64-encoded)" >&2
  exit 1
fi

TMP_KEY=$(mktemp)
echo "${GPU_SSH_KEY}" | base64 --decode > "${TMP_KEY}"
chmod 600 "${TMP_KEY}"

scp -i "${TMP_KEY}" -P "${GPU_SSH_PORT}" "${STACK_COMPOSE_FILE}" \
  "${GPU_SSH_USER}@${GPU_SSH_HOST}:${REMOTE_DIR}/docker-compose.yml"

ssh -i "${TMP_KEY}" -p "${GPU_SSH_PORT}" "${GPU_SSH_USER}@${GPU_SSH_HOST}" <<EOF
set -e
cd ${REMOTE_DIR}
docker login ghcr.io -u ${GHCR_USER:-jjziets} -p ${GHCR_PAT:?GHCR_PAT is required}
docker compose --env-file ${ENV_FILE_REMOTE} pull
docker compose --env-file ${ENV_FILE_REMOTE} up -d movie-maker-a movie-maker-b
EOF

rm -f "${TMP_KEY}"

