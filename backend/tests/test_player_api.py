import os
import shutil
import subprocess
import tempfile
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

from backend.app.config import Settings
from backend.app.main import create_app
from backend.app.services.player import PlayerService

REAL_POPEN = subprocess.Popen


def headless_mpv(command, **kwargs):
    # Exercise the production IPC client without opening a desktop window.
    if not any(arg.startswith("--input-ipc-server=") for arg in command):
        return REAL_POPEN(command, **kwargs)
    command = [arg for arg in command if arg not in (
        "--fullscreen", "--force-window=immediate",
    )]
    return REAL_POPEN([*command, "--vo=null", "--ao=null"], **kwargs)


class ApiFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sg-", dir="/tmp")
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.videos = root / "videos"
        self.videos.mkdir()
        self.settings = Settings(self.videos, root / "run", "test-token-" * 4)
        self.client = self.enterContext(TestClient(create_app(self.settings)))
        self.client.headers["Authorization"] = f"Bearer {self.settings.api_token}"


class ApiTests(ApiFixture):
    def test_health_and_authentication(self):
        with TestClient(create_app(Settings(
            self.videos, Path(self.temp.name) / "other", "secret" * 8
        ))) as public:
            self.assertEqual(public.get("/api/health").json(), {"status": "ok"})
            for path in ("status", "start", "pause", "resume", "stop", "next", "previous", "restart"):
                response = public.get(f"/api/player/{path}") if path == "status" else public.post(f"/api/player/{path}")
                self.assertEqual(response.status_code, 401, path)
            public.headers["Authorization"] = "Bearer wrong"
            self.assertEqual(public.post("/api/player/start").status_code, 401)

    def test_initial_status_and_empty_folder(self):
        self.assertEqual(self.client.get("/api/player/status").json()["state"], "stopped")
        self.assertEqual(self.client.post("/api/player/start").status_code, 409)
        self.assertEqual(self.client.post("/api/player/restart").status_code, 409)
        for action in ("pause", "resume", "next", "previous"):
            self.assertEqual(self.client.post(f"/api/player/{action}").status_code, 409)

    def test_missing_mpv_returns_german_error(self):
        (self.videos / "video.mp4").touch()
        with patch("backend.app.services.player.subprocess.Popen", side_effect=FileNotFoundError):
            response = self.client.post("/api/player/start")
        self.assertEqual(response.status_code, 503)
        self.assertIn("MPV konnte nicht gestartet", response.json()["detail"])

    def test_server_lock(self):
        other = PlayerService(self.settings)
        with self.assertRaisesRegex(RuntimeError, "anderen Server"):
            other.open()

    def test_external_symlinks_are_ignored(self):
        outside = Path(self.temp.name) / "private.mp4"
        outside.touch()
        (self.videos / "linked.mp4").symlink_to(outside)
        self.assertEqual(self.client.get("/api/player/status").json()["video_count"], 0)

    def test_short_environment_token_is_rejected(self):
        with patch.dict(os.environ, {"SIGNAGE_API_TOKEN": "short"}):
            with self.assertRaises(ValueError):
                Settings.from_env()

    def test_missing_token_is_created_and_persisted(self):
        runtime = Path(self.temp.name) / "settings"
        with patch.dict(os.environ, {"SIGNAGE_RUNTIME_DIR": str(runtime)}):
            os.environ.pop("SIGNAGE_API_TOKEN", None)
            first = Settings.from_env()
            second = Settings.from_env()
        self.assertGreaterEqual(len(first.api_token), 32)
        self.assertEqual(first.api_token, second.api_token)
        self.assertEqual((runtime / "api-token").read_text().strip(), first.api_token)
        self.assertEqual((runtime / "api-token").stat().st_mode & 0o777, 0o600)
        self.assertEqual(runtime.stat().st_mode & 0o777, 0o700)
        with TestClient(create_app(first)) as client:
            self.assertEqual(client.get("/api/player/status").status_code, 401)
            client.headers["Authorization"] = f"Bearer {first.api_token}"
            self.assertEqual(client.get("/api/player/status").status_code, 200)

    def test_concurrent_settings_share_one_generated_token(self):
        runtime = Path(self.temp.name) / "concurrent-settings"
        with patch.dict(os.environ, {"SIGNAGE_RUNTIME_DIR": str(runtime)}):
            os.environ.pop("SIGNAGE_API_TOKEN", None)
            with ThreadPoolExecutor(max_workers=6) as executor:
                tokens = list(executor.map(lambda _: Settings.from_env().api_token, range(6)))
        self.assertEqual(len(set(tokens)), 1)

    def test_explicit_token_takes_priority(self):
        runtime = Path(self.temp.name) / "custom-settings"
        token = "custom-token-" * 4
        with patch.dict(os.environ, {
            "SIGNAGE_RUNTIME_DIR": str(runtime), "SIGNAGE_API_TOKEN": token,
        }):
            self.assertEqual(Settings.from_env().api_token, token)
        self.assertFalse(runtime.exists())


@unittest.skipUnless(shutil.which("mpv") and shutil.which("ffmpeg"), "MPV and FFmpeg are required")
class RealMpvTests(ApiFixture):
    def setUp(self):
        super().setUp()
        subprocess.run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
            "color=c=black:s=32x32:r=1", "-t", "30", "-c:v", "mpeg4",
            str(self.videos / "01 first.mp4"),
        ], check=True, stdin=subprocess.DEVNULL, timeout=15)
        shutil.copyfile(self.videos / "01 first.mp4", self.videos / "02 second.mp4")
        self.launch = self.enterContext(patch(
            "backend.app.services.player.subprocess.Popen", side_effect=headless_mpv
        ))

    def wait_status(self, state, filename=None):
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            result = self.client.get("/api/player/status").json()
            if result["state"] == state and (filename is None or result["current_file"] == filename):
                return result
            time.sleep(0.05)
        self.fail(f"Expected {state}/{filename}, received {result}")

    def post(self, action):
        response = self.client.post(f"/api/player/{action}")
        self.assertEqual(response.status_code, 200, response.text)
        return response.json()

    def test_full_playback_lifecycle(self):
        self.post("start")
        self.wait_status("playing", "01 first.mp4")
        player = self.client.app.state.player
        process = player._process
        self.post("pause")
        self.wait_status("paused")
        self.post("start")
        self.wait_status("playing")
        self.assertIs(player._process, process)
        self.post("pause")
        self.post("resume")
        self.wait_status("playing")
        self.post("next")
        self.wait_status("playing", "02 second.mp4")
        self.post("previous")
        self.wait_status("playing", "01 first.mp4")
        self.post("start")
        self.assertIs(player._process, process)
        self.post("stop")
        self.wait_status("stopped")
        self.assertIsNone(process.poll())
        self.assertEqual(self.client.post("/api/player/resume").status_code, 409)
        self.post("start")
        self.wait_status("playing")
        self.post("restart")
        self.wait_status("playing", "01 first.mp4")
        self.assertIsNot(player._process, process)
        self.assertIsNotNone(process.poll())
        current = player._process
        player.close()
        self.assertIsNotNone(current.poll())

    def test_parallel_start_uses_one_process(self):
        with ThreadPoolExecutor(max_workers=6) as executor:
            replies = list(executor.map(lambda _: self.client.post("/api/player/start"), range(6)))
        self.assertTrue(all(reply.status_code == 200 for reply in replies))
        self.assertEqual(self.launch.call_count, 1)
        self.wait_status("playing")

    def test_stop_before_start_keeps_idle_process(self):
        self.post("stop")
        self.wait_status("stopped")
        self.assertIsNone(self.client.app.state.player._process.poll())

    def test_process_crash_is_reported_and_start_recovers(self):
        self.post("start")
        self.wait_status("playing")
        process = self.client.app.state.player._process
        process.kill()
        process.wait(timeout=3)
        self.wait_status("unreachable")
        self.post("start")
        self.wait_status("playing")

    def test_ipc_failure_is_reported(self):
        self.post("start")
        self.wait_status("playing")
        self.client.app.state.player.socket_path.unlink()
        self.wait_status("error")
        response = self.client.post("/api/player/pause")
        self.assertEqual(response.status_code, 503)
        self.assertIn("nicht erreichbar", response.json()["detail"])


if __name__ == "__main__":
    unittest.main()
