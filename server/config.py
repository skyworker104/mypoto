"""PhotoNest Server Configuration."""

import os
import secrets
from pathlib import Path

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Server
    server_name: str = "PhotoNest Server"
    server_id: str = ""
    host: str = "0.0.0.0"
    port: int = 8080
    debug: bool = False

    # Paths
    data_dir: Path = Path.home() / "photonest" / "data"
    storage_dir: Path = Path.home() / "photonest" / "originals"
    thumbnail_dir: Path = Path.home() / "photonest" / "thumbnails"
    ai_dir: Path = Path.home() / "photonest" / "ai"

    # Database
    db_path: Path = Path.home() / "photonest" / "data" / "photonest.db"

    # JWT
    jwt_secret: str = ""
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 1440  # 24 hours
    refresh_token_expire_days: int = 30

    # Pairing
    pin_length: int = 6
    pin_expire_seconds: int = 300  # 5 minutes
    pin_max_attempts: int = 5
    pin_lockout_seconds: int = 600  # 10 minutes

    # AI
    ai_models_dir: Path = Path.home() / "photonest" / "ai" / "models"
    face_match_threshold: float = 0.4
    ai_auto_process: bool = True  # auto-process new uploads

    # mDNS
    mdns_service_type: str = "_photonest._tcp.local."

    model_config = {"env_prefix": "PHOTONEST_"}

    def ensure_dirs(self) -> None:
        """Create all required directories."""
        for d in [self.data_dir, self.storage_dir, self.thumbnail_dir, self.ai_dir, self.ai_models_dir]:
            d.mkdir(parents=True, exist_ok=True)

    def ensure_secrets(self) -> None:
        """Generate secrets if not set, persist to file so they survive restarts."""
        secrets_file = self.data_dir / ".secrets"
        saved = {}
        if secrets_file.exists():
            for line in secrets_file.read_text().strip().splitlines():
                if "=" in line:
                    k, v = line.split("=", 1)
                    saved[k.strip()] = v.strip()

        if not self.jwt_secret:
            self.jwt_secret = saved.get("jwt_secret", "") or secrets.token_urlsafe(32)
        if not self.server_id:
            self.server_id = saved.get("server_id", "") or f"pn_{secrets.token_hex(4)}"

        # Persist for next restart
        secrets_file.write_text(f"jwt_secret={self.jwt_secret}\nserver_id={self.server_id}\n")


settings = Settings()
settings.ensure_dirs()
settings.ensure_secrets()
