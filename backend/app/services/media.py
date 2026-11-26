import json
import os
import subprocess
import tempfile
import hashlib
import threading
from collections.abc import AsyncIterable
from pathlib import Path
from typing import Callable

from fastapi import HTTPException
from starlette.concurrency import run_in_threadpool
from PIL import Image, ImageOps, UnidentifiedImageError

from ..config import Settings
from ..media_types import IMAGE_FORMATS, MEDIA_EXTS, media_type
from .player import PlayerService


class MediaService:
    def __init__(self, settings: Settings, player: PlayerService):
        self.settings = settings
        self.root = settings.videos_dir.resolve()
        self.player = player
        self.deletion_check: Callable[[str], None] | None = None
        self._image_lock = threading.RLock()

    def _path(self, name: str) -> Path:
        if (not name or name.startswith(".") or name != name.strip()
                or "/" in name or "\\" in name or len(name.encode("utf-8")) > 200
                or any(ord(char) < 32 or ord(char) == 127 for char in name)):
            raise HTTPException(400, "Ungültiger Dateiname.")
        if Path(name).suffix.lower() not in MEDIA_EXTS:
            raise HTTPException(415, "Erlaubt sind JPG, JPEG, PNG, WebP, MP4, MKV, MOV und WebM.")
        return self.root / name

    @staticmethod
    def _info(path: Path) -> dict:
        return {"id": path.name, "name": path.name,
                "type": media_type(path.name), "size_bytes": path.stat().st_size}

    def list(self) -> list[dict]:
        result = []
        if not self.root.is_dir():
            return result
        for path in sorted(self.root.iterdir()):
            if not path.is_file() or path.suffix.lower() not in MEDIA_EXTS:
                continue
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

    def _validate_image(self, path: Path, suffix: str) -> None:
        with self._image_lock:
            try:
                with Image.open(path) as image:
                    if image.format != IMAGE_FORMATS[suffix]:
                        raise HTTPException(422, "Bildinhalt und Dateiendung stimmen nicht überein.")
                    if image.width * image.height > 16_000_000:
                        raise HTTPException(422, "Das Bild darf höchstens 16 Millionen Pixel enthalten.")
                    if getattr(image, "n_frames", 1) != 1:
                        raise HTTPException(422, "Bitte ein einzelnes, nicht animiertes Bild verwenden.")
                    image.verify()
                with Image.open(path) as image:
                    image.load()
            except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as error:
                raise HTTPException(422, "Die Datei enthält kein gültiges Bild.") from error

    def preview(self, name: str) -> bytes:
        with self._image_lock:
            self.get(name)
            if media_type(name) != "image":
                raise HTTPException(415, "Eine Vorschau ist nur für Bilder verfügbar.")
            source = self._path(name)
            target = self._preview_target(source)
            if not target.is_file():
                self._validate_image(source, source.suffix.lower())
                target.parent.mkdir(parents=True, exist_ok=True)
                temporary = tempfile.NamedTemporaryFile(dir=target.parent, prefix=".preview-", delete=False)
                temporary.close()
                try:
                    with Image.open(source) as image:
                        thumbnail = ImageOps.exif_transpose(image)
                        thumbnail.thumbnail((320, 180))
                        thumbnail.convert("RGBA").save(temporary.name, format="PNG")
                    os.replace(temporary.name, target)
                finally:
                    Path(temporary.name).unlink(missing_ok=True)
            return target.read_bytes()

    def _preview_target(self, source: Path) -> Path:
        key = hashlib.sha256(f"{source.name}:{source.stat().st_mtime_ns}".encode()).hexdigest()
        return self.settings.runtime_dir / "previews" / f"{key}.png"

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
            validator = self._validate_image if media_type(name) == "image" else self._validate_video
            await run_in_threadpool(validator, path, target.suffix.lower())
            try:
                # Publish only complete, validated files, without overwriting a race winner.
                os.link(path, target)
            except FileExistsError:
                raise HTTPException(409, "Eine Datei mit diesem Namen ist bereits vorhanden.")
            return {"id": name, "name": name, "type": media_type(name), "size_bytes": size}
        finally:
            path.unlink(missing_ok=True)

    def delete(self, name: str) -> None:
        path = self._path(name)
        with self.player.guard_media_deletion(path):
            self.get(name)
            if self.deletion_check:
                self.deletion_check(name)
            try:
                with self._image_lock:
                    preview = self._preview_target(path)
                    path.unlink()
                    preview.unlink(missing_ok=True)
            except FileNotFoundError:
                raise HTTPException(404, "Datei nicht gefunden.")
