import io
import shutil
import subprocess
import time
import unittest
from dataclasses import replace
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient
from PIL import Image

from backend.app.main import create_app
from backend.app.services.playlists import PlaylistService
from backend.tests.test_player_api import ApiFixture, headless_mpv


def image_bytes(format="PNG", size=(64, 40)):
    output = io.BytesIO()
    Image.new("RGB", size, "blue").save(output, format=format)
    return output.getvalue()


class PlaylistFixture(ApiFixture):
    def upload(self, name="Bild.png", content=None):
        response = self.client.post("/api/media/upload", params={"filename": name},
                                    content=image_bytes() if content is None else content)
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()

    def create(self, name="Schaufenster", items=None, **settings):
        response = self.client.post("/api/playlists", json={
            "name": name, "items": [] if items is None else items, **settings,
        })
        self.assertEqual(response.status_code, 201, response.text)
        return response.json()


class ImagePlaylistTests(PlaylistFixture):
    def test_image_formats_preview_and_cleanup(self):
        for extension, format in (("jpg", "JPEG"), ("jpeg", "JPEG"), ("png", "PNG"), ("webp", "WEBP")):
            item = self.upload(f"Bild.{extension}", image_bytes(format))
            self.assertEqual(item["type"], "image")
        self.assertEqual(self.client.get("/api/player/status").json()["image_count"], 4)
        response = self.client.get("/api/media/Bild.png/preview")
        self.assertEqual(response.status_code, 200)
        with Image.open(io.BytesIO(response.content)) as image:
            self.assertLessEqual(image.width, 320)
            self.assertLessEqual(image.height, 180)
        del self.client.headers["Authorization"]
        self.assertEqual(self.client.get("/api/media/Bild.png/preview").status_code, 401)
        self.client.headers["Authorization"] = f"Bearer {self.settings.api_token}"
        self.assertEqual(self.client.delete("/api/media/Bild.png?confirm=true").status_code, 204)
        self.assertEqual(list((self.settings.runtime_dir / "previews").iterdir()), [])

    def test_fake_mismatched_oversized_and_animated_images_are_rejected(self):
        samples = [("fake.png", b"not an image"), ("wrong.jpg", image_bytes()),
                   ("truncated.jpg", image_bytes("JPEG")[:-30]),
                   ("large.png", image_bytes(size=(4001, 4000)))]
        animation = io.BytesIO()
        Image.new("RGB", (8, 8), "red").save(animation, format="WEBP", save_all=True,
              append_images=[Image.new("RGB", (8, 8), "green")], duration=100, loop=0)
        samples.append(("animated.webp", animation.getvalue()))
        for name, content in samples:
            response = self.client.post("/api/media/upload", params={"filename": name}, content=content)
            self.assertEqual(response.status_code, 422, response.text)
        self.assertEqual(list(self.videos.iterdir()), [])

    def test_create_edit_select_delete_and_protect_references(self):
        self.upload()
        item = self.create(items=["Bild.png"])
        self.assertEqual(self.client.delete("/api/media/Bild.png?confirm=true").status_code, 409)
        response = self.client.put("/api/playlists/selected", json={"id": item["id"]})
        self.assertEqual(response.json()["selected_id"], item["id"])
        item.update(name="Abend", image_duration=12, loop=False)
        saved = self.client.put(f"/api/playlists/{item['id']}", json={k: v for k, v in item.items() if k != "id"})
        self.assertEqual(saved.status_code, 200, saved.text)
        self.assertEqual(saved.json()["revision"], 2)
        self.assertEqual(self.client.delete(f"/api/playlists/{item['id']}").status_code, 400)
        self.assertEqual(self.client.delete(f"/api/playlists/{item['id']}?confirm=true").status_code, 204)
        self.assertIsNone(self.client.get("/api/playlists").json()["selected_id"])
        self.assertEqual(self.client.delete("/api/media/Bild.png?confirm=true").status_code, 204)

    def test_empty_missing_and_invalid_lists_are_rejected(self):
        item = self.create()
        self.assertEqual(self.client.post(f"/api/playlists/{item['id']}/start").status_code, 409)
        for body in ({"name": " "}, {"name": "Test", "items": ["../private.png"]},
                     {"name": "Test", "image_duration": 0}, {"name": "Test", "items": ["missing.png"]}):
            self.assertIn(self.client.post("/api/playlists", json=body).status_code, (400, 404, 422))
        self.assertEqual(self.client.put("/api/playlists/selected", json={"id": "missing"}).status_code, 404)
        self.assertEqual(self.client.post("/api/playlists", json={"name": item["name"]}).status_code, 409)
        del self.client.headers["Authorization"]
        self.assertEqual(self.client.get("/api/playlists").status_code, 401)
        self.assertEqual(self.client.post("/api/playlists", json={"name": "Private"}).status_code, 401)
        self.assertEqual(self.client.put("/api/playlists/selected", json={"id": None}).status_code, 401)

    def test_stale_update_and_atomic_save_failure_do_not_lose_data(self):
        item = self.create()
        url = f"/api/playlists/{item['id']}"
        body = {k: v for k, v in item.items() if k != "id"}
        self.assertEqual(self.client.put(url, json=body).status_code, 200)
        self.assertEqual(self.client.put(url, json=body).status_code, 409)
        service = self.client.app.state.playlists
        before = service.list()
        original = service.path.read_bytes()
        with patch("backend.app.services.playlists.os.replace", side_effect=OSError("disk failure")):
            with self.assertRaises(OSError):
                service.select(item["id"])
        self.assertEqual(service.list(), before)
        self.assertEqual(service.path.read_bytes(), original)
        self.assertEqual(list(service.path.parent.glob(".playlists-*")), [])

    def test_saved_lists_survive_new_service_and_corruption_is_not_overwritten(self):
        self.upload()
        item = self.create(items=["Bild.png"])
        self.client.put("/api/playlists/selected", json={"id": item["id"]})
        reloaded = PlaylistService(self.settings, self.client.app.state.media)
        self.assertEqual(reloaded.list(), self.client.app.state.playlists.list())
        path = reloaded.path
        path.write_text("{broken json")
        with self.assertRaisesRegex(RuntimeError, "beschädigt"):
            PlaylistService(self.settings, self.client.app.state.media)
        self.assertEqual(path.read_text(), "{broken json")


@unittest.skipUnless(shutil.which("mpv") and shutil.which("ffmpeg"), "MPV and FFmpeg required")
class RealPlaylistTests(PlaylistFixture):
    def setUp(self):
        super().setUp()
        self.enterContext(patch("backend.app.services.player.subprocess.Popen", side_effect=headless_mpv))
        self.upload("01.png")
        self.upload("02.png", image_bytes("PNG", (20, 30)))
        subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=black:s=32x32:r=1",
                        "-t", "30", "-c:v", "mpeg4", str(self.videos / "03.mp4")],
                       check=True, timeout=15, stdin=subprocess.DEVNULL)

    def wait_file(self, filename, state="playing", timeout=5):
        deadline = time.monotonic() + timeout
        result = None
        while time.monotonic() < deadline:
            result = self.client.get("/api/player/status").json()
            if result["current_file"] == filename and result["state"] == state:
                return result
            time.sleep(0.04)
        self.fail(f"Expected {filename}/{state}, received {result}")

    def test_mixed_playback_duration_pause_selection_and_restart(self):
        first = self.create("Gemischt", ["01.png", "03.mp4"], image_duration=1)
        second = self.create("Bilder", ["02.png"], image_duration=2)
        self.assertEqual(self.client.post(f"/api/playlists/{first['id']}/start").status_code, 200)
        status = self.wait_file("01.png")
        self.assertEqual(status["current_playlist_id"], first["id"])
        player = self.client.app.state.player
        process = player._process
        self.client.post("/api/player/pause")
        self.wait_file("01.png", "paused")
        time.sleep(1.1)
        self.wait_file("01.png", "paused")
        self.client.post("/api/player/resume")
        self.wait_file("03.mp4")
        self.assertEqual(self.client.post("/api/player/pause").status_code, 200)
        self.wait_file("03.mp4", "paused")
        self.assertEqual(self.client.post("/api/player/resume").status_code, 200)
        self.assertEqual(self.client.post(f"/api/playlists/{second['id']}/start").status_code, 200)
        self.wait_file("02.png")
        self.assertIs(player._process, process)
        self.assertEqual(self.client.get("/api/playlists").json()["selected_id"], second["id"])
        self.assertEqual(self.client.delete(f"/api/playlists/{second['id']}?confirm=true").status_code, 409)
        self.assertEqual(self.client.post("/api/player/stop").status_code, 200)
        self.assertEqual(self.client.post("/api/player/start").status_code, 200)
        self.wait_file("02.png")
        self.assertEqual(self.client.post("/api/player/restart").status_code, 200)
        self.wait_file("02.png")

    def test_image_only_list_ends_and_loop_list_repeats(self):
        item = self.create("Einmal", ["01.png"], image_duration=1, loop=False)
        self.client.post(f"/api/playlists/{item['id']}/start")
        self.wait_file("01.png")
        self.wait_file(None, "stopped", timeout=4)
        item = self.create("Wiederholen", ["01.png", "02.png"], image_duration=1, loop=True)
        self.client.post(f"/api/playlists/{item['id']}/start")
        self.wait_file("01.png")
        self.wait_file("02.png")
        self.wait_file("01.png")

    def test_default_playback_includes_images_without_saved_lists(self):
        self.assertEqual(self.client.post("/api/player/start").status_code, 200)
        status = self.wait_file("01.png")
        self.assertEqual(status["image_count"], 2)
        self.assertEqual(status["current_playlist_name"], "Alle Medien")

    def test_selected_list_survives_application_shutdown_and_restart(self):
        settings = replace(self.settings, runtime_dir=Path(self.temp.name) / "restart")
        headers = {"Authorization": f"Bearer {settings.api_token}"}
        with TestClient(create_app(settings)) as first:
            item = first.post("/api/playlists", headers=headers, json={
                "name": "Nach Neustart", "items": ["02.png"], "image_duration": 10,
            }).json()
            self.assertEqual(first.put("/api/playlists/selected", headers=headers,
                                       json={"id": item["id"]}).status_code, 200)
        with TestClient(create_app(settings)) as second:
            self.assertEqual(second.get("/api/playlists", headers=headers).json()["selected_id"], item["id"])
            self.assertEqual(second.post("/api/player/start", headers=headers).status_code, 200)
            deadline = time.monotonic() + 4
            while time.monotonic() < deadline:
                status = second.get("/api/player/status", headers=headers).json()
                if status["current_file"] == "02.png":
                    self.assertEqual(status["current_playlist_id"], item["id"])
                    break
                time.sleep(0.04)
            else:
                self.fail(f"Selected playlist was not restored: {status}")
