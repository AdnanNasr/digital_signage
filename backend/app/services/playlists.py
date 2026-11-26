import copy
import json
import os
import tempfile
from pathlib import Path
from uuid import uuid4

from fastapi import HTTPException
from pydantic import ValidationError

from ..config import Settings
from ..models.playlist import PlaylistDocument, PlaylistInput
from .media import MediaService
from .player import PlaybackPlan


class PlaylistService:
    def __init__(self, settings: Settings, media: MediaService):
        self.media = media
        self.player = media.player
        self._lock = self.player.lock
        self.path = settings.playlists_file or settings.runtime_dir / "playlists.json"
        self._document = {"selected_id": None, "playlists": []}
        if self.path.exists():
            try:
                if self.path.stat().st_size > 8 * 1024 * 1024:
                    raise ValueError("Playlist file is too large")
                document = PlaylistDocument.model_validate(json.loads(self.path.read_text()))
                ids = [item.id for item in document.playlists]
                if len(ids) != len(set(ids)) or (document.selected_id is not None and document.selected_id not in ids):
                    raise ValueError("Invalid playlist identifiers")
                self._document = document.model_dump()
            except (ValueError, ValidationError) as error:
                raise RuntimeError("Die gespeicherten Wiedergabelisten sind beschädigt. Bitte die Sicherung prüfen.") from error

    def list(self) -> dict:
        with self._lock:
            return copy.deepcopy(self._document)

    def _find(self, playlist_id: str, document: dict | None = None) -> dict:
        document = self._document if document is None else document
        for item in document["playlists"]:
            if item["id"] == playlist_id:
                return item
        raise HTTPException(404, "Wiedergabeliste nicht gefunden.")

    def _save(self, document: dict) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        temporary = tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=self.path.parent,
                                               prefix=".playlists-", delete=False)
        try:
            with temporary:
                json.dump(document, temporary, ensure_ascii=False, indent=2)
                temporary.flush()
                os.fsync(temporary.fileno())
            os.replace(temporary.name, self.path)
            self._document = document
        finally:
            Path(temporary.name).unlink(missing_ok=True)

    def _validate(self, data: PlaylistInput, playlist_id: str | None = None) -> None:
        if any(item["name"].casefold() == data.name.casefold() and item["id"] != playlist_id
               for item in self._document["playlists"]):
            raise HTTPException(409, "Eine Wiedergabeliste mit diesem Namen ist bereits vorhanden.")
        for name in data.items:
            self.media.get(name)

    def create(self, data: PlaylistInput) -> dict:
        with self._lock:
            if len(self._document["playlists"]) >= 50:
                raise HTTPException(409, "Es sind höchstens 50 Wiedergabelisten möglich.")
            self._validate(data)
            item = {**data.model_dump(), "id": uuid4().hex, "revision": 1}
            document = self.list()
            document["playlists"].append(item)
            self._save(document)
            return copy.deepcopy(item)

    def update(self, playlist_id: str, data: PlaylistInput) -> dict:
        with self._lock:
            current = self._find(playlist_id)
            if data.revision != current["revision"]:
                raise HTTPException(409, "Die Liste wurde inzwischen geändert. Bitte neu laden.")
            self._validate(data, playlist_id)
            document = self.list()
            item = self._find(playlist_id, document)
            item.update(data.model_dump())
            item["revision"] += 1
            self._save(document)
            return copy.deepcopy(item)

    def select(self, playlist_id: str | None) -> dict:
        with self._lock:
            if playlist_id is not None:
                self._find(playlist_id)
            document = self.list()
            document["selected_id"] = playlist_id
            self._save(document)
            return document

    def delete(self, playlist_id: str) -> None:
        with self._lock:
            self._find(playlist_id)
            if self.player.is_playing_playlist(playlist_id):
                raise HTTPException(409, "Bitte zuerst die Wiedergabe dieser Liste stoppen.")
            document = self.list()
            document["playlists"] = [item for item in document["playlists"] if item["id"] != playlist_id]
            if document["selected_id"] == playlist_id:
                document["selected_id"] = None
            self._save(document)

    def ensure_media_unused(self, media_id: str) -> None:
        with self._lock:
            if any(media_id in item["items"] for item in self._document["playlists"]):
                raise HTTPException(409, "Die Datei wird in einer Wiedergabeliste verwendet. Bitte zuerst aus der Liste entfernen.")

    def plan(self, playlist_id: str) -> PlaybackPlan:
        with self._lock:
            item = self._find(playlist_id)
            if not item["items"]:
                raise HTTPException(409, "Die Wiedergabeliste ist leer.")
            files = []
            for name in item["items"]:
                self.media.get(name)
                files.append(self.media.root / name)
            return PlaybackPlan(playlist_id, item["name"], files, item["image_duration"], item["loop"])

    def selected_plan(self) -> PlaybackPlan | None:
        with self._lock:
            selected = self._document["selected_id"]
            return self.plan(selected) if selected is not None else None

    def start(self, playlist_id: str) -> dict:
        with self._lock:
            plan = self.plan(playlist_id)
            self.select(playlist_id)
            return self.player.play(plan)
