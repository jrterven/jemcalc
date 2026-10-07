"""Environment configuration, loaded once without logging secret values."""

from dataclasses import dataclass
from functools import lru_cache
import os
from pathlib import Path

from dotenv import load_dotenv


@dataclass(frozen=True)
class Settings:
    pilot_token: str = ""
    mathpix_app_id: str = ""
    mathpix_app_key: str = ""
    openai_api_key: str = ""
    elevenlabs_api_key: str = ""
    openai_interpreter_model: str = "gpt-6-luna"
    cas_timeout_seconds: float = 10.0
    recognition_timeout_seconds: float = 30.0
    max_image_bytes: int = 8 * 1024 * 1024
    max_audio_seconds: int = 120

    @property
    def configured_providers(self) -> dict[str, bool]:
        return {
            "mathpix": bool(self.mathpix_app_id and self.mathpix_app_key),
            "openai": bool(self.openai_api_key),
            "scribe": bool(self.elevenlabs_api_key),
        }


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    load_dotenv(Path(__file__).resolve().parent.parent / ".env", override=False)
    timeout = float(os.getenv("CAS_TIMEOUT_SECONDS", "10"))
    if not 0.05 <= timeout <= 30:
        raise ValueError("CAS_TIMEOUT_SECONDS must be between 0.05 and 30")
    return Settings(
        pilot_token=os.getenv("PILOT_TOKEN", ""),
        mathpix_app_id=os.getenv("MATHPIX_APP_ID", ""),
        mathpix_app_key=os.getenv("MATHPIX_APP_KEY", ""),
        openai_api_key=os.getenv("OPENAI_API_KEY", ""),
        elevenlabs_api_key=os.getenv("ELEVENLABS_API_KEY", ""),
        openai_interpreter_model=os.getenv("OPENAI_INTERPRETER_MODEL", "gpt-6-luna"),
        cas_timeout_seconds=timeout,
    )
