import asyncio
import shutil
import subprocess
import tempfile
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from pathlib import Path
from unittest.mock import patch

from backend.tests.test_player_api import ApiFixture, headless_mpv


class MediaApiTests(ApiFixture):
    def upload(self, name, content):
        return self.client.post("/api/media/upload", params={"filename": name}, content=content)

    def test_authentication_required(self):
        del self.client.headers["Authorization"]
        self.assertEqual(self.client.get("/api/media").status_code, 401)
        self.assertEqual(self.upload("test.mp4", b"video").status_code, 401)
        self.assertEqual(self.client.get("/api/media/test.mp4").status_code, 401)
        self.assertEqual(self.client.delete("/api/media/test.mp4?confirm=true").status_code, 401)
        self.assertEqual(list(self.videos.iterdir()), [])

    def test_list_get_and_confirmation(self):
        (self.videos / "clip.mp4").write_bytes(b"existing")
        (self.videos / "notes.txt").write_text("hidden")
        outside = Path(self.temp.name) / "outside.mp4"
        outside.write_bytes(b"private")
        (self.videos / "linked.mp4").symlink_to(outside)
        result = self.client.get("/api/media").json()
        self.assertEqual([item["id"] for item in result], ["clip.mp4"])
        self.assertEqual(result[0]["size_bytes"], 8)
        self.assertEqual(self.client.get("/api/media/clip.mp4").json(), result[0])
        self.assertEqual(self.client.get("/api/media/linked.mp4").status_code, 404)
        self.assertEqual(self.client.delete("/api/media/clip.mp4").status_code, 400)
        self.assertTrue((self.videos / "clip.mp4").exists())
        self.assertEqual(self.client.delete("/api/media/clip.mp4?confirm=true").status_code, 204)
        self.assertEqual(self.client.delete("/api/media/clip.mp4?confirm=true").status_code, 404)
        self.assertTrue(outside.exists())

    def test_invalid_names_and_extensions(self):
        for name in ("../escape.mp4", "folder/clip.mp4", "folder\\clip.mp4", ".hidden.mp4",
                     "bad\nname.mp4", "\x00.mp4", " x.mp4", "x" * 201 + ".mp4"):
            with self.subTest(name=name):
                self.assertEqual(self.upload(name, b"content").status_code, 400)
        self.assertEqual(self.upload("script.py", b"content").status_code, 415)
        self.assertEqual(list(self.videos.iterdir()), [])

    def test_empty_and_duplicate_uploads(self):
        self.assertEqual(self.upload("empty.mp4", b"").status_code, 422)
        (self.videos / "existing.mp4").write_bytes(b"original")
        self.assertEqual(self.upload("existing.mp4", b"replacement").status_code, 409)
        self.assertEqual((self.videos / "existing.mp4").read_bytes(), b"original")
        self.assertEqual([path.name for path in self.videos.iterdir()], ["existing.mp4"])

    def test_size_limit_with_and_without_content_length(self):
        settings = replace(self.settings, max_upload_bytes=8)
        self.client.app.state.settings = settings
        self.client.app.state.media.settings = settings
        self.assertEqual(self.upload("large.mp4", b"x" * 9).status_code, 413)
        response = self.upload("stream.mp4", iter([b"12345", b"67890"]))
        self.assertEqual(response.status_code, 413)
        self.assertEqual(list(self.videos.iterdir()), [])

    def test_interrupted_upload_cleans_temporary_file(self):
        async def interrupted():
            yield b"partial upload"
            self.assertEqual(self.client.app.state.media.list(), [])
            raise RuntimeError("connection interrupted")

        with self.assertRaisesRegex(RuntimeError, "interrupted"):
            asyncio.run(self.client.app.state.media.upload("clip.mp4", interrupted()))
        self.assertEqual(list(self.videos.iterdir()), [])

    def test_probe_unavailable_cleans_temporary_file(self):
        self.client.app.state.media.settings = replace(
            self.settings, ffprobe_binary="/not-installed/ffprobe"
        )
        response = self.upload("clip.mp4", b"content")
        self.assertEqual(response.status_code, 503)
        self.assertEqual(list(self.videos.iterdir()), [])


@unittest.skipUnless(all(shutil.which(tool) for tool in ("ffmpeg", "ffprobe", "mpv")),
                     "FFmpeg, FFprobe and MPV are required")
class RealMediaTests(ApiFixture):
    @classmethod
    def setUpClass(cls):
        cls.samples = tempfile.TemporaryDirectory(prefix="sg-samples-", dir="/tmp")
        cls.addClassCleanup(cls.samples.cleanup)
        cls.contents = {}
        for suffix in ("mp4", "mov", "mkv", "webm"):
            path = Path(cls.samples.name) / f"sample.{suffix}"
            subprocess.run([
                "ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=black:s=32x32:r=1",
                "-t", "30", "-c:v", "libvpx-vp9" if suffix == "webm" else "mpeg4", str(path),
            ], check=True, stdin=subprocess.DEVNULL, timeout=15)
            cls.contents[suffix] = path.read_bytes()

    def upload(self, name, content):
        return self.client.post("/api/media/upload", params={"filename": name}, content=content)

    def test_all_supported_containers(self):
        for suffix, content in self.contents.items():
            with self.subTest(suffix=suffix):
                response = self.upload(f"Grüße clip.{suffix}", content)
                self.assertEqual(response.status_code, 201, response.text)
                self.assertEqual(response.json()["size_bytes"], len(content))
        self.assertEqual(len(self.client.get("/api/media").json()), 4)
        self.assertEqual(self.client.get("/api/player/status").json()["video_count"], 4)

    def test_fake_video_and_wrong_container_are_rejected(self):
        for content in (b"not a video", self.contents["webm"]):
            response = self.upload("fake.mp4", content)
            self.assertEqual(response.status_code, 422, response.text)
        self.assertEqual(list(self.videos.iterdir()), [])

    def test_audio_only_is_rejected(self):
        path = Path(self.temp.name) / "audio.mp4"
        subprocess.run([
            "ffmpeg", "-v", "error", "-f", "lavfi", "-i", "anullsrc", "-t", "0.1",
            "-c:a", "aac", str(path),
        ], check=True, stdin=subprocess.DEVNULL, timeout=15)
        self.assertEqual(self.upload("audio.mp4", path.read_bytes()).status_code, 422)
        self.assertEqual(list(self.videos.iterdir()), [])

    def test_simultaneous_uploads_never_overwrite(self):
        media = self.client.app.state.media
        validate = media._validate_video
        barrier = threading.Barrier(2)

        def wait_for_both(path, suffix):
            validate(path, suffix)
            barrier.wait(timeout=5)

        with patch.object(media, "_validate_video", side_effect=wait_for_both):
            with ThreadPoolExecutor(max_workers=2) as executor:
                replies = list(executor.map(
                    lambda _: self.upload("same.mp4", self.contents["mp4"]), range(2)
                ))
        self.assertEqual(sorted(reply.status_code for reply in replies), [201, 409])
        self.assertEqual((self.videos / "same.mp4").read_bytes(), self.contents["mp4"])
        self.assertEqual([path.name for path in self.videos.iterdir()], ["same.mp4"])

    def test_unknown_player_state_blocks_deletion(self):
        self.enterContext(patch("backend.app.services.player.subprocess.Popen", side_effect=headless_mpv))
        self.assertEqual(self.upload("clip.mp4", self.contents["mp4"]).status_code, 201)
        self.assertEqual(self.client.post("/api/player/start").status_code, 200)
        self.client.app.state.player.socket_path.unlink()
        response = self.client.delete("/api/media/clip.mp4?confirm=true")
        self.assertEqual(response.status_code, 503)
        self.assertTrue((self.videos / "clip.mp4").exists())

    def test_delete_requires_stopping_loaded_playlist(self):
        self.enterContext(patch("backend.app.services.player.subprocess.Popen", side_effect=headless_mpv))
        for name in ("first.mp4", "second.mp4"):
            self.assertEqual(self.upload(name, self.contents["mp4"]).status_code, 201)
        self.assertEqual(self.client.post("/api/player/start").status_code, 200)
        for name in ("first.mp4", "second.mp4"):
            response = self.client.delete(f"/api/media/{name}?confirm=true")
            self.assertEqual(response.status_code, 409, response.text)
            self.assertTrue((self.videos / name).exists())
        self.assertEqual(self.client.post("/api/player/pause").status_code, 200)
        self.assertEqual(self.client.delete("/api/media/first.mp4?confirm=true").status_code, 409)
        self.assertEqual(self.client.post("/api/player/stop").status_code, 200)
        self.assertEqual(self.client.delete("/api/media/first.mp4?confirm=true").status_code, 204)
        self.assertEqual(self.client.post("/api/player/start").status_code, 200)
        playlist = self.client.app.state.player._command("get_property", "playlist")
        self.assertEqual([Path(entry["filename"]).name for entry in playlist], ["second.mp4"])


if __name__ == "__main__":
    unittest.main()
