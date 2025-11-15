from __future__ import annotations
import logging
from typing import Iterable

import httpx
import uvicorn
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware

from .config import Settings, get_settings
from .schemas import HealthResponse, SessionRequest, SessionResponse

logger = logging.getLogger("framepack_wrapper")


def _allowed_origins(settings: Settings) -> list[str]:
    origins: Iterable[str] = {
        settings.public_base_url,
        settings.public_base_url.rstrip("/"),
        settings.public_base_url.rstrip("/").replace("https://", "http://"),
    }
    return [origin for origin in origins if origin]


async def _probe_comfyui(settings: Settings) -> bool:
    """Hit a lightweight endpoint to ensure ComfyUI is up."""
    url = settings.comfyui_url.rstrip("/") + "/system_stats"
    try:
        async with httpx.AsyncClient(timeout=3.0) as client:
            resp = await client.get(url)
            resp.raise_for_status()
        return True
    except Exception as exc:  # noqa: BLE001 - log and downgrade
        logger.warning("ComfyUI health probe failed: %s", exc)
        return False


def _require_wp_headers(request: Request) -> dict[str, str]:
    email = request.headers.get("x-webui-email")
    api_key = request.headers.get("x-user-api-key")
    name = request.headers.get("x-webui-name", "")

    if not email or not api_key:
        raise HTTPException(status_code=401, detail="Missing WordPress SSO headers")

    return {
        "email": email,
        "api_key": api_key,
        "name": name or email.split("@")[0],
    }


def create_app(settings: Settings | None = None) -> FastAPI:
    settings = settings or get_settings()
    logging.basicConfig(level=settings.log_level.upper())

    app = FastAPI(
        title="FramePack Wrapper",
        version="0.1.0",
        docs_url="/__docs",
        redoc_url="/__redoc",
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=_allowed_origins(settings),
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.get("/healthz", response_model=HealthResponse, tags=["ops"])
    async def health(_: Settings = Depends(get_settings)) -> HealthResponse:  # noqa: ANN201
        healthy = await _probe_comfyui(settings)
        status = "ok" if healthy else "degraded"
        return HealthResponse(status=status, comfyui_url=settings.comfyui_url)

    @app.post("/session", response_model=SessionResponse, tags=["session"])
    async def create_session(  # noqa: ANN201
        payload: SessionRequest,
        request: Request,
        config: Settings = Depends(get_settings),
    ):
        user = _require_wp_headers(request)

        logger.info(
            "Session requested by %s workflow=%s",
            user["email"],
            payload.workflow,
        )

        response = SessionResponse(
            comfyui_url=config.comfyui_url,
            workflow=payload.workflow,
            user_email=user["email"],
        )
        return response

    return app


app = create_app()


def main() -> None:
    settings = get_settings()
    uvicorn.run(
        "framepack_wrapper.app:app",
        host=settings.wrapper_host,
        port=settings.wrapper_port,
        log_level=settings.log_level,
        reload=False,
      # ssl maybe
    )


if __name__ == "__main__":
    main()

