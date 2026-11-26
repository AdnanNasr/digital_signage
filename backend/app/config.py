import os
from dataclasses import dataclass
from pathlib import Path

from python_project.main import get_path


@dataclass(frozen=True)
class Settings:
    videos_dir: Path
    runtime_dir: Path
    api_token: str
    mpv_binary: str = "mpv"
    ipc_timeout: float = 3.0

    @classmethod
    def from_env(cls) -> "Settings":
        token = os.environ.get("SIGNAGE_API_TOKEN", "")
        if len(token) < 32:
            raise ValueError("SIGNAGE_API_TOKEN muss mindestens 32 Zeichen enthalten.")
        return cls(
            videos_dir=Path(os.environ.get("SIGNAGE_VIDEOS_DIR", str(get_path()))).resolve(),
            runtime_dir=Path(os.environ.get(
                "SIGNAGE_RUNTIME_DIR", str(Path(__file__).resolve().parents[1] / "runtime")
            )).resolve(),
            api_token=token,
            mpv_binary=os.environ.get("SIGNAGE_MPV_BINARY", "mpv"),
        )
