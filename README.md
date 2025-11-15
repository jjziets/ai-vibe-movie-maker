# AI Vibe Movie Maker

Infrastructure-as-code for hosting CryptoLabs' AI Vibe Movie Maker experience on top of **ComfyUI + FramePack**, wrapped with WordPress SSO enforcement and GPU-friendly deployment tooling.

## Goals
- Deterministic Docker build that bundles ComfyUI, FramePack, and the FramePack Wrapper service.
- Dual-GPU aware docker-compose definition that can pin workloads per GPU.
- GitHub Actions pipeline that builds/pushes the image to Docker Hub (or any registry you prefer) and optionally triggers the GPU server rollout.
- Documentation + helper scripts so the service can be embedded at `https://www.cryptolabs.co.za/ai-vibe-movie-maker/`.

## Repository Layout
```
docs/                     # Architecture, SSO, deployment notes
docker/ComfyUI.Dockerfile # CUDA-enabled container build
docker/entrypoint.sh      # Boots ComfyUI + wrapper inside the container
compose/docker-compose.gpu.yml  # Example multi-GPU stack
configs/comfyui.env.example     # Shared secrets (copy to comfyui.env)
scripts/deploy.sh         # Helper used locally / CI to update GPU host
src/framepack_wrapper/    # Placeholder FastAPI service for WP SSO
.github/workflows/build.yml      # CI to build/push Docker image
```

## Quick Start (local GPU workstation)
```bash
cp configs/comfyui.env.example configs/comfyui.env
# adjust CUDA_VISIBLE_DEVICES (0,1 for NVLink pair) inside comfyui.env
docker compose -f compose/docker-compose.gpu.yml --env-file configs/comfyui.env up -d
```
The default compose file launches a single container with `CUDA_VISIBLE_DEVICES=0,1`, so both 48 GB cards are available to FramePack through NVLink. If you prefer per‑GPU isolation, set `CUDA_VISIBLE_DEVICES=0` (or `=1`) and duplicate the service definition.

## Deployment Pipeline
1. Push to `main`.
2. GitHub Actions (`.github/workflows/build.yml`) builds the image with Buildx, tags it as `${DOCKER_USERNAME}/ai-vibe-movie-maker:latest`, and pushes to Docker Hub.
3. (Optional) The same workflow can SSH into the GPU server (41.193.204.66:101) and run `scripts/deploy.sh` to pull & restart the stack. Secrets required:
   - `DOCKER_USERNAME` / `DOCKER_PASSWORD` – Docker Hub credentials for publishing & pulling.
   - `GPU_SSH_KEY` – Base64-encoded private key for the server.
   - `GPU_SSH_USER`, `GPU_SSH_HOST`, `GPU_SSH_PORT`.

## WordPress Embedding
- The Movie Maker page simply hosts a shortcode/iframe that points to `framepack.ai.cryptolabs.co.za`.
- Nginx on the GPU host enforces WordPress SSO via the `/wp-json/cryptolabs/v1/framepack/auth` endpoint.
- The wrapper service (`src/framepack_wrapper`) consumes the forwarded headers (`X-Webui-*`) and injects user metadata / API keys into ComfyUI sessions.

## Next Steps
- Flesh out the FastAPI wrapper with the actual business logic (credits, workflow selection, etc.).
- Sync nginx + WordPress plugin changes from `cryptolabs-ai-platform`.
- Wire automated deployment into the existing `deploy-all.sh` flow once this repo is production ready.

