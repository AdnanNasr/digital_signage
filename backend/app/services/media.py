import json
import os
import subprocess
import tempfile
from collections.abc import AsyncIterable
from pathlib import Path

from fastapi import HTTPException
from starlette.concurrency import run_in_threadpool

from python_project.main import VIDEO_EXTS, get_videos

from ..config import Settings
from .player import PlayerService


class MediaService:
    def __init__(self, settings: Settings, player: PlayerService):
        self.settings = settings
        self.root = settings.videos_dir.resolve()
        self.player = player

    def _path(self, name: str) -> Path:
        if (not name or name.startswith(".") or name != name.strip()
                or "/" in name or "\\" in name or len(name.encode("utf-8")) > 200
                or any(ord(char) < 32 or ord(char) == 127 for char in name)):
            raise HTTPException(400, "Ungültiger Dateiname.")
        if Path(name).suffix.lower() not in VIDEO_EXTS:
            raise HTTPException(415, "Erlaubt sind MP4, MKV, MOV und WebM.")
        return self.root / name

    @staticmethod
    def _info(path: Path) -> dict:
        return {"id": path.name, "name": path.name,
                "type": "video", "size_bytes": path.stat().st_size}

    def list(self) -> list[dict]:
        result = []
        for path in get_videos(self.root):
            if not path.is_symlink() and not path.name.startswith("."):
                try:
                    result.append(self._info(path))
                except FileNotFoundError:
                    continue
        return result

    def get(self, name: str) -> dict:
        path = self._path(name)
        if path.is_symlink() or not path.is_file():
            raise HTTPException(404, "Datei nicht gefunden.")
        try:
            return self._info(path)
        except FileNotFoundError:
            raise HTTPException(404, "Datei nicht gefunden.")

    def _validate_video(self, path: Path, suffix: str) -> None:
        try:
            result = subprocess.run([
                self.settings.ffprobe_binary, "-v", "error",
                "-protocol_whitelist", "file,pipe",
                "-f", "mov" if suffix in {".mp4", ".mov"} else "matroska",
                "-show_entries", "stream=codec_type:stream_disposition=attached_pic",
                "-of", "json", str(path),
            ], capture_output=True, timeout=15, check=False, stdin=subprocess.DEVNULL)
        except FileNotFoundError:
            raise HTTPException(503, "Videoprüfung nicht verfügbar. Bitte FFmpeg installieren.")
        except subprocess.TimeoutExpired:
            raise HTTPException(422, "Die Videoprüfung hat zu lange gedauert.")
        try:
            streams = json.loads(result.stdout).get("streams", [])
        except (ValueError, AttributeError):
            streams = []
        if result.returncode != 0 or not any(
            stream.get("codec_type") == "video"
            and not stream.get("disposition", {}).get("attached_pic", 0)
            for stream in streams
        ):
            raise HTTPException(422, "Die Datei enthält kein gültiges Video im angegebenen Format.")

    async def upload(self, name: str, chunks: AsyncIterable[bytes]) -> dict:
        target = self._path(name)
        if target.exists() or target.is_symlink():
            raise HTTPException(409, "Eine Datei mit diesem Namen ist bereits vorhanden.")
        self.root.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.NamedTemporaryFile(prefix=".upload-", suffix=".part", dir=self.root, delete=False)
        path = Path(temporary.name)
        size = 0
        try:
            with temporary:
                async for chunk in chunks:
                    size += len(chunk)
                    if size > self.settings.max_upload_bytes:
                        raise HTTPException(413, "Die Datei überschreitet die erlaubte Größe.")
                    await run_in_threadpool(temporary.write, chunk)
                await run_in_threadpool(temporary.flush)
                await run_in_threadpool(os.fsync, temporary.fileno())
            if size == 0:
                raise HTTPException(422, "Die Datei ist leer.")
            await run_in_threadpool(self._validate_video, path, target.suffix.lower())
            try:
                # Publish only complete, validated files, without overwriting a race winner.
                os.link(path, target)
            except FileExistsError:
                raise HTTPException(409, "Eine Datei mit diesem Namen ist bereits vorhanden.")
            return {"id": name, "name": name, "type": "video", "size_bytes": size}
        finally:
            path.unlink(missing_ok=True)

    def delete(self, name: str) -> None:
        path = self._path(name)
        with self.player.guard_media_deletion(path):
            self.get(name)
            try:
                path.unlink()
            except FileNotFoundError:
                raise HTTPException(404, "Datei nicht gefunden.")
