# AI Vibe Movie Maker

Infrastructure-as-code for hosting CryptoLabs' AI Vibe Movie Maker experience on top of **ComfyUI + FramePack**, wrapped with WordPress SSO enforcement and GPU-friendly deployment tooling.

## Goals
- Deterministic Docker build that bundles ComfyUI, FramePack, and the FramePack Wrapper service.
- Dual-GPU aware docker-compose definition that can pin workloads per GPU.
- GitHub Actions pipeline that builds/pushes the image to GHCR and optionally triggers the GPU server rollout.
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
docker compose -f compose/docker-compose.gpu.yml --env-file configs/comfyui.env up -d
```
The default compose file starts one ComfyUI instance bound to GPU0. Uncomment the second service to utilize both GPUs.

## Deployment Pipeline
1. Push to `main`.
2. GitHub Actions (`.github/workflows/build.yml`) builds the image with Buildx, tags it as `ghcr.io/jjziets/ai-vibe-movie-maker:latest`, and pushes.
3. (Optional) The same workflow can SSH into the GPU server (41.193.204.66:101) and run `scripts/deploy.sh` to pull & restart the stack. Secrets required:
   - `GHCR_PAT` – Personal access token allowing GHCR push/pull.
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

