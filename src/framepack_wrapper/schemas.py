from datetime import datetime, timezone
from uuid import uuid4
from pydantic import BaseModel, Field


class SessionRequest(BaseModel):
    """Incoming payload describing the workflow/prompt to run."""

    workflow: str | None = Field(default=None, description="Human-friendly workflow slug")
    prompt: str | None = Field(default=None, description="Optional natural language prompt")
    seed: int | None = Field(default=None, description="Seed override")


class SessionResponse(BaseModel):
    """Minimal descriptor returned to the frontend iframe."""

    session_id: str = Field(default_factory=lambda: uuid4().hex)
    comfyui_url: str
    workflow: str | None = None
    user_email: str
    issued_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class HealthResponse(BaseModel):
    status: str = "ok"
    comfyui_url: str | None = None
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

