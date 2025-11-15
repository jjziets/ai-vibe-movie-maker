from functools import lru_cache
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Runtime configuration sourced from environment variables."""

    comfyui_url: str = "http://127.0.0.1:9090"
    public_base_url: str = "https://framepack.ai.cryptolabs.co.za"
    wrapper_host: str = "0.0.0.0"
    wrapper_port: int = 9443
    log_level: str = "info"
    data_dir: str = "/data"
    output_dir: str = "/outputs"
    framepack_license_key: str | None = None
    wordpress_header_prefix: str = "x-webui"
    framepack_max_context: int = 2048
    framepack_tea_cache: bool = False

    class Config:
        env_prefix = ""
        case_sensitive = False


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()

