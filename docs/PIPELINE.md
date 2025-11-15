# CI / CD Pipeline

## Build Stage
- Trigger: every push to `main` (manual `workflow_dispatch` supported).
- Action: `.github/workflows/build.yml`.
- Steps:
  1. Checkout repo.
  2. Configure Docker Buildx.
  3. Authenticate to Docker Hub via `DOCKER_USERNAME` / `DOCKER_PASSWORD`.
  4. Build `docker/ComfyUI.Dockerfile`.
  5. Push image as `${DOCKER_USERNAME}/ai-vibe-movie-maker:latest`.

## Deploy Stage
- Optional step toggled automatically when both `GPU_SSH_HOST` and `GPU_SSH_KEY` secrets exist.
- Uses `scripts/deploy.sh`, which:
  1. Decodes `GPU_SSH_KEY` (base64) into a temp file.
  2. Copies `compose/docker-compose.gpu.yml` to `/home/vast/ai-vibe-movie-maker/docker-compose.yml`.
  3. SSHes into the GPU server (`41.193.204.66:101` by default).
  4. Runs `docker compose pull && docker compose up -d movie-maker-a movie-maker-b`.

## Required GitHub Secrets
| Secret | Purpose |
|--------|---------|
| `DOCKER_USERNAME` | Docker Hub account used for publishing images. |
| `DOCKER_PASSWORD` | Docker Hub access token/password for the account. |
| `GPU_SSH_KEY` | Base64-encoded private key that can log into the GPU server. |
| `GPU_SSH_HOST` | Hostname/IP of the GPU box. |
| `GPU_SSH_PORT` | SSH port (default 101). |
| `GPU_SSH_USER` | SSH username (default `root`). |

## Server Preparation
- Ensure `/home/vast/ai-vibe-movie-maker` exists with:
  - `comfyui.env` (copy of `configs/comfyui.env`, filled with secrets).
  - `docker-compose.yml` (managed by the deploy script).
- Install Docker + NVIDIA Container Toolkit and (optionally) log into Docker Hub once to cache credentials.
- Update nginx + WordPress plugin to point at the `movie-maker-*` services.

