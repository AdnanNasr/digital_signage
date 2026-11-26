import fcntl
import os
import secrets
from dataclasses import dataclass
from pathlib import Path

from python_project.main import get_path


def get_allowed_origins() -> tuple[str, ...]:
    return tuple(origin.strip() for origin in os.environ.get(
        "SIGNAGE_ALLOWED_ORIGINS", "http://localhost:8080,http://127.0.0.1:8080"
    ).split(",") if origin.strip())


def load_api_token(runtime_dir: Path) -> str:
    configured = os.environ.get("SIGNAGE_API_TOKEN")
    if configured is not None:
        return configured
    runtime_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    runtime_dir.chmod(0o700)
    descriptor = os.open(runtime_dir / "api-token", os.O_RDWR | os.O_CREAT, 0o600)
    with os.fdopen(descriptor, "r+", encoding="utf-8") as token_file:
        os.fchmod(token_file.fileno(), 0o600)
        fcntl.flock(token_file, fcntl.LOCK_EX)
        token = token_file.read().strip()
        if not token:
            token = secrets.token_urlsafe(32)
            token_file.write(token + "\n")
            token_file.flush()
            os.fsync(token_file.fileno())
        return token


@dataclass(frozen=True)
class Settings:
    videos_dir: Path
    runtime_dir: Path
    api_token: str
    mpv_binary: str = "mpv"
    ipc_timeout: float = 3.0
    max_upload_bytes: int = 512 * 1024 * 1024
    ffprobe_binary: str = "ffprobe"
    allowed_origins: tuple[str, ...] = ("http://localhost:8080", "http://127.0.0.1:8080")

    @classmethod
    def from_env(cls) -> "Settings":
        runtime_dir = Path(os.environ.get(
            "SIGNAGE_RUNTIME_DIR", str(Path(__file__).resolve().parents[1] / "runtime")
        )).resolve()
        token = load_api_token(runtime_dir)
        if len(token) < 8:
            raise ValueError("SIGNAGE_API_TOKEN muss mindestens 8 Zeichen enthalten.")
        max_upload_mb = int(os.environ.get("SIGNAGE_MAX_UPLOAD_MB", "512"))
        if max_upload_mb < 1:
            raise ValueError("SIGNAGE_MAX_UPLOAD_MB muss mindestens 1 sein.")
        return cls(
            videos_dir=Path(os.environ.get("SIGNAGE_VIDEOS_DIR", str(get_path()))).resolve(),
            runtime_dir=runtime_dir,
            api_token=token,
            mpv_binary=os.environ.get("SIGNAGE_MPV_BINARY", "mpv"),
            max_upload_bytes=max_upload_mb * 1024 * 1024,
            ffprobe_binary=os.environ.get("SIGNAGE_FFPROBE_BINARY", "ffprobe"),
            allowed_origins=get_allowed_origins(),
        )
