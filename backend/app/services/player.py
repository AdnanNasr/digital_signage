import fcntl
import json
import logging
import socket
import subprocess
import threading
import time
from pathlib import Path

from python_project.main import get_videos

from ..config import Settings

logger = logging.getLogger(__name__)


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
            ], stdin=subprocess.DEVNULL)
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

    def _videos(self) -> list[Path]:
        root = self.settings.videos_dir.resolve()
        return [path.resolve() for path in get_videos(root)
                if path.resolve().is_relative_to(root)]

    def _load_videos(self) -> None:
        videos = self._videos()
        if not videos:
            raise PlayerError("Keine Videos vorhanden.", 409)
        self._ensure_running()
        for index, video in enumerate(videos):
            self._command("loadfile", str(video), "replace" if index == 0 else "append")
        self._command("set_property", "pause", False)

    def start(self) -> dict:
        with self._lock:
            if self._process is not None and self._process.poll() is None:
                if not self._command("get_property", "idle-active"):
                    self._command("set_property", "pause", False)
                    return self.status()
            self._load_videos()
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
            return self.status()

    def restart(self) -> dict:
        with self._lock:
            if not self._videos():
                raise PlayerError("Keine Videos vorhanden.", 409)
            self._terminate()
            self._load_videos()
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
        return {"state": state, "label": label, "reachable": reachable,
                "current_file": filename, "video_count": len(self._videos())}

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
