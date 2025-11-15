# AI Vibe Movie Maker – Architecture

## Components
| Component | Description |
|-----------|-------------|
| **ComfyUI** | Base node editor + execution engine. Runs inside the Docker container with CUDA 12.1 drivers. |
| **FramePack** | Workflow + asset bundle providing the Movie Maker capabilities (video prompt composer, storyboard loops, etc.). Installed into `ComfyUI/custom_nodes/framepack`. |
| **FramePack Wrapper** | Lightweight FastAPI application that lives in the same container, handles WordPress SSO headers, routes user preset selections to ComfyUI, and exposes health/readiness probes. |
| **Nginx (GPU host)** | Terminates TLS for `framepack.ai.cryptolabs.co.za`, calls WordPress `auth_request`, and forwards traffic to the container. |
| **WordPress Plugin** | Issues API keys + credit balances via `WP_REST` endpoint (`/wp-json/cryptolabs/v1/framepack/auth`). |

## Data Flow
1. User logs into `cryptolabs.co.za` and visits `/ai-vibe-movie-maker/`.
2. WordPress shortcode loads an iframe that points to `https://framepack.ai.cryptolabs.co.za`.
3. Nginx intercepts the request, runs `auth_request` against WordPress, captures headers (`X-Webui-Email`, `X-User-Api-Key`, etc.), then forwards the request to the container.
4. FramePack Wrapper validates headers, starts ComfyUI in trusted mode, maps the user to a workspace on shared storage, and emits SSE/WebSocket events back to the iframe.
5. Completed renders are written to `/outputs/$USER_ID/…`; WordPress UI fetches them via the wrapper API.

## GPU Layout
- `compose/docker-compose.gpu.yml` ships two services (`movie-maker-a`, `movie-maker-b`).
- Each service sets `CUDA_VISIBLE_DEVICES` so we can dedicate a GPU per container (GPU0/1).
- Persistent assets (checkpoints, VAEs, LORAs, FramePack bundles) mounted from `/var/lib/cryptolabs/movie-maker`.

## Security
- No direct public access: everything goes through WordPress SSO and nginx.
- API tokens flow from WordPress → nginx → wrapper; ComfyUI never sees WordPress cookies.
- Secrets (FramePack license, HuggingFace token, etc.) live in `configs/comfyui.env` and are injected via compose.

## Deploy Story
- Build & push image via GitHub Actions.
- GPU host runs `docker compose pull && docker compose up -d movie-maker-a movie-maker-b`.
- `scripts/deploy.sh` is idempotent and intended to be executed by CI or a human operator.

