import fcntl
import json
import logging
import socket
import subprocess
import threading
import time
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from python_project.main import get_videos

from ..config import Settings
from ..desktop_session import desktop_environment
from ..media_types import MEDIA_EXTS, IMAGE_FORMATS

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class PlaybackPlan:
    id: str | None
    name: str
    files: list[Path]
    image_duration: int = 10
    loop: bool = True


class PlayerError(Exception):
    def __init__(self, message: str, status_code: int = 503):
        super().__init__(message)
        self.status_code = status_code


class PlayerService:
    """Own one MPV process and serialize commands through its private IPC socket."""

    def __init__(self, settings: Settings):
        self.settings = settings
        self.socket_path = settings.runtime_dir / "mpv.sock"
        self._lock = threading.RLock()
        self._process: subprocess.Popen | None = None
        self._ownership = None
        self.playlist_source: Callable[[], PlaybackPlan | None] | None = None
        self._current_plan: PlaybackPlan | None = None
        self.fit_mode = "contain"

    @property
    def lock(self):
        return self._lock

    def open(self) -> None:
        self.settings.runtime_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.settings.runtime_dir.chmod(0o700)
        self._ownership = (self.settings.runtime_dir / "player.lock").open("a")
        try:
            fcntl.flock(self._ownership, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self._ownership.close()
            self._ownership = None
            raise RuntimeError("Der Player wird bereits von einem anderen Server verwaltet.")

    def _command(self, *command):
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
                connection.settimeout(self.settings.ipc_timeout)
                connection.connect(str(self.socket_path))
                connection.sendall((json.dumps({
                    "command": command, "request_id": 1,
                }) + "\n").encode())
                with connection.makefile("rb") as stream:
                    while line := stream.readline(1024 * 1024):
                        response = json.loads(line)
                        if response.get("request_id") != 1:
                            continue
                        if response.get("error") != "success":
                            logger.warning("MPV command %s failed: %s", command[0], response)
                            raise PlayerError("Der Player konnte den Befehl nicht ausführen.")
                        return response.get("data")
        except (OSError, ValueError) as error:
            raise PlayerError("Der Player ist nicht erreichbar.") from error
        raise PlayerError("Der Player hat die Verbindung geschlossen.")

    def _ensure_running(self) -> None:
        if self._process is not None and self._process.poll() is None:
            return
        if self._ownership is None:
            raise PlayerError("Der Player-Dienst wurde nicht initialisiert.")
        self.socket_path.unlink(missing_ok=True)
        try:
            self._process = subprocess.Popen([
                self.settings.mpv_binary,
                "--no-config", "--fullscreen", "--loop-playlist=inf", "--no-audio",
                "--idle=yes", "--force-window=immediate", "--background-color=#000000",
                "--no-terminal", "--osc=no", "--osd-level=0", "--input-default-bindings=no",
                f"--input-ipc-server={self.socket_path}",
                f"--keepaspect={'no' if self.fit_mode == 'stretch' else 'yes'}",
                f"--panscan={1 if self.fit_mode == 'cover' else 0}",
            ], stdin=subprocess.DEVNULL, env=desktop_environment())
        except OSError as error:
            raise PlayerError("MPV konnte nicht gestartet werden. Bitte Installation prüfen.") from error
        deadline = time.monotonic() + self.settings.ipc_timeout
        while time.monotonic() < deadline:
            if self._process.poll() is not None:
                break
            try:
                self._command("get_property", "idle-active")
                return
            except PlayerError:
                time.sleep(0.05)
        self._terminate()
        raise PlayerError("MPV ist nicht bereit. Bitte die Bildschirm-Sitzung prüfen.")

    def current_fit_mode(self) -> str:
        with self._lock:
            if self._process is not None and self._process.poll() is None:
                aspect = self._command('get_property', 'keepaspect')
                scan = self._command('get_property', 'panscan')
                return 'stretch' if not aspect else ('cover' if scan == 1 else 'contain' if scan == 0 else 'custom')
            return self.fit_mode

    def set_fit_mode(self, mode: str) -> None:
        properties = {
            'contain': {'keepaspect': True, 'panscan': 0.0},
            'cover': {'keepaspect': True, 'panscan': 1.0},
            'stretch': {'keepaspect': False, 'panscan': 0.0},
        }
        if mode not in properties:
            raise PlayerError('Ungültige Bildschirmdarstellung.', 422)
        with self._lock:
            if self._process is not None and self._process.poll() is None:
                previous = {name: self._command('get_property', name)
                            for name in properties[mode]}
                try:
                    for name, value in properties[mode].items():
                        self._command('set_property', name, value)
                except PlayerError:
                    for name, value in previous.items():
                        self._command('set_property', name, value)
                    raise
            self.fit_mode = mode

    def _videos(self) -> list[Path]:
        root = self.settings.videos_dir.resolve()
        return [path.resolve() for path in get_videos(root)
                if not path.is_symlink() and not path.name.startswith(".")
                and path.resolve().is_relative_to(root)]

    def _media_files(self) -> list[Path]:
        root = self.settings.videos_dir.resolve()
        if not root.is_dir():
            return []
        return sorted(path for path in root.iterdir() if path.is_file() and not path.is_symlink()
                      and not path.name.startswith(".") and path.suffix.lower() in MEDIA_EXTS)

    def _configured_plan(self) -> PlaybackPlan:
        selected = self.playlist_source() if self.playlist_source else None
        return selected or PlaybackPlan(None, "Alle Medien", self._media_files())

    def _load_plan(self, plan: PlaybackPlan) -> None:
        if not plan.files:
            raise PlayerError("Keine Medien vorhanden.", 409)
        root = self.settings.videos_dir.resolve()
        if any(not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(root)
               for path in plan.files):
            raise PlayerError("Eine Datei der Wiedergabeliste ist nicht verfügbar.", 409)
        self._ensure_running()
        try:
            self._command("set_property", "pause", True)
            self._command("set_property", "loop-playlist", "inf" if plan.loop else "no")
            self._command("set_property", "image-display-duration", plan.image_duration)
            for index, path in enumerate(plan.files):
                self._command("loadfile", str(path.resolve()), "replace" if index == 0 else "append")
            self._current_plan = plan
            self._command("set_property", "pause", False)
        except PlayerError:
            self._current_plan = None
            try:
                self._command("stop")
            except PlayerError:
                pass
            raise

    def play(self, plan: PlaybackPlan) -> dict:
        with self._lock:
            self._load_plan(plan)
            return self.status()

    def is_playing_playlist(self, playlist_id: str) -> bool:
        with self._lock:
            return bool(self._current_plan and self._current_plan.id == playlist_id
                        and self._process is not None and self._process.poll() is None
                        and not self._command("get_property", "idle-active"))

    def start(self) -> dict:
        with self._lock:
            if self._process is not None and self._process.poll() is None:
                if not self._command("get_property", "idle-active"):
                    self._command("set_property", "pause", False)
                    return self.status()
            self._load_plan(self._configured_plan())
            return self.status()

    def pause(self) -> dict:
        return self._active_command("set_property", "pause", True)

    def resume(self) -> dict:
        return self._active_command("set_property", "pause", False)

    def next(self) -> dict:
        return self._active_command("playlist-next", "force")

    def previous(self) -> dict:
        return self._active_command("playlist-prev", "force")

    def _active_command(self, *command) -> dict:
        with self._lock:
            if self._process is None or self._process.poll() is not None:
                raise PlayerError("Der Player ist nicht gestartet.", 409)
            if self._command("get_property", "idle-active"):
                raise PlayerError("Es wird keine Datei wiedergegeben.", 409)
            self._command(*command)
            return self.status()

    def stop(self) -> dict:
        with self._lock:
            self._ensure_running()
            self._command("stop")
            self._current_plan = None
            return self.status()

    def restart(self) -> dict:
        with self._lock:
            plan = self._configured_plan()
            if not plan.files:
                raise PlayerError("Keine Medien vorhanden.", 409)
            self._terminate()
            self._load_plan(plan)
            return self.status()

    def status(self) -> dict:
        with self._lock:
            if self._process is None:
                return self._status("stopped", "Gestoppt", False)
            if self._process.poll() is not None:
                return self._status("unreachable", "Nicht erreichbar", False)
            try:
                if self._command("get_property", "idle-active"):
                    return self._status("stopped", "Gestoppt", True)
                paused = self._command("get_property", "pause")
                path = self._command("get_property", "path")
                return self._status(
                    "paused" if paused else "playing",
                    "Pausiert" if paused else "Wird wiedergegeben", True,
                    Path(path).name if path else None,
                )
            except PlayerError:
                return self._status("error", "Fehler", False)

    def _status(self, state, label, reachable, filename=None) -> dict:
        current = self._current_plan if state in {"playing", "paused"} else None
        return {"state": state, "label": label, "reachable": reachable,
                "current_file": filename, "video_count": len(self._videos()),
                "image_count": sum(path.suffix.lower() in IMAGE_FORMATS for path in self._media_files()),
                "current_playlist_id": current.id if current else None,
                "current_playlist_name": current.name if current else None}

    @contextmanager
    def guard_media_deletion(self, path: Path):
        # Hold the command lock until deletion finishes, so start cannot race it.
        with self._lock:
            if self._process is not None and self._process.poll() is None:
                playlist = self._command("get_property", "playlist")
                if any(Path(entry["filename"]).resolve() == path.resolve() for entry in playlist):
                    raise PlayerError(
                        "Die Datei ist in der Wiedergabe. Bitte zuerst die Wiedergabe stoppen.", 409
                    )
            yield

    def _terminate(self) -> None:
        if self._process is not None:
            if self._process.poll() is None:
                self._process.terminate()
                try:
                    self._process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    self._process.kill()
                    self._process.wait(timeout=3)
            self._process = None
        self.socket_path.unlink(missing_ok=True)

    def close(self) -> None:
        with self._lock:
            try:
                self._terminate()
            finally:
                if self._ownership is not None:
                    self._ownership.close()
                    self._ownership = None
