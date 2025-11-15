"""
FramePack wrapper package.

Provides a lightweight FastAPI service that:
  - Verifies WordPress SSO headers forwarded via nginx auth_request.
  - Issues short-lived session descriptors for the ComfyUI frontend.
  - Exposes health/readiness endpoints for GPU monitoring.
"""

