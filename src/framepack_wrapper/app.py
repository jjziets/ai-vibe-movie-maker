from __future__ import annotations
import base64
import hashlib
import hmac
import json
import logging
import time
from typing import Iterable

import httpx
import uvicorn
from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, RedirectResponse

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

    @app.get("/auth/trusted/login", tags=["auth"])
    async def trusted_login(
        request: Request,
        payload: str,
        sig: str,
        redirect: str = "/",
        config: Settings = Depends(get_settings),
    ):
        """
        WordPress SSO endpoint - validates signed payload and sets session cookie.
        Mirrors Open WebUI's /api/v1/auth/trusted/login flow.
        """
        # Verify signature
        secret = config.wp_sso_shared_secret
        if not secret:
            logger.error("WP_SSO_SHARED_SECRET not configured")
            raise HTTPException(status_code=500, detail="SSO not configured")

        logger.info("Using WP SSO secret prefix: %s", config.wp_sso_shared_secret[:8])

        payload_bytes = payload.encode("utf-8")
        logger.info(
            "SSO payload debug len=%s head=%s",
            len(payload_bytes),
            payload_bytes[:48].hex(),
        )

        expected_sig = hmac.new(
            secret.encode('utf-8'),
            payload_bytes,
            hashlib.sha256
        ).hexdigest()
        logger.info(
            "SSO signature debug sig=%s expected=%s",
            sig[:32],
            expected_sig[:32],
        )

        if not hmac.compare_digest(sig, expected_sig):
            logger.warning(
                "Invalid SSO signature from %s - expected=%s got=%s payload=%s",
                request.client.host, expected_sig[:16], sig[:16], payload[:50]
            )
            raise HTTPException(status_code=401, detail="Invalid signature")

        # Decode payload
        try:
            payload_json = base64.b64decode(payload).decode('utf-8')
            data = json.loads(payload_json)
        except Exception as e:
            logger.error("Failed to decode SSO payload: %s", e)
            raise HTTPException(status_code=400, detail="Invalid payload")

        # Validate timestamp (5 minute window)
        timestamp = data.get('timestamp', 0)
        if abs(time.time() - timestamp) > 300:
            logger.warning("SSO payload expired for %s", data.get('email'))
            raise HTTPException(status_code=401, detail="Payload expired")

        email = data.get('email')
        name = data.get('name', email)
        api_key = data.get('apiKey')

        if not email or not api_key:
            raise HTTPException(status_code=400, detail="Missing email or apiKey")

        logger.info("SSO login successful for %s", email)

        # Create session token (simple signed cookie)
        session_data = {
            'email': email,
            'name': name,
            'api_key': api_key,
            'timestamp': int(time.time())
        }
        session_json = json.dumps(session_data)
        session_token = base64.b64encode(session_json.encode('utf-8')).decode('utf-8')
        session_sig = hmac.new(
            secret.encode('utf-8'),
            session_token.encode('utf-8'),
            hashlib.sha256
        ).hexdigest()

        # Redirect to requested path with session cookie
        response = RedirectResponse(url=redirect, status_code=302)
        response.set_cookie(
            key="framepack_session",
            value=f"{session_token}.{session_sig}",
            max_age=86400,  # 24 hours
            secure=True,
            httponly=True,
            samesite="none",
            domain=None  # Current domain only
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

