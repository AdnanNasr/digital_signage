import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

from backend import run
from backend.app.desktop_session import require_desktop_user
from backend.app.main import create_app


class StartupUserTests(unittest.TestCase):
    def test_regular_desktop_user_is_allowed(self):
        with patch('backend.app.desktop_session.os.geteuid', return_value=1000):
            require_desktop_user()

    def test_sudo_root_is_rejected_with_actionable_message(self):
        with patch('backend.app.desktop_session.os.geteuid', return_value=0):
            with self.assertRaisesRegex(RuntimeError, 'ohne sudo'):
                require_desktop_user()

    def test_launcher_rejects_root_before_starting_uvicorn(self):
        with patch('sys.argv', ['run.py']), patch('backend.app.desktop_session.os.geteuid', return_value=0), patch.object(run.uvicorn, 'run') as start:
            with self.assertRaisesRegex(SystemExit, 'ohne sudo'):
                run.main()
            start.assert_not_called()

    def test_direct_uvicorn_entrypoint_rejects_root_before_creating_runtime(self):
        with tempfile.TemporaryDirectory(prefix='sg-startup-', dir='/tmp') as temporary:
            runtime = Path(temporary) / 'runtime'
            with patch.dict('os.environ', {'SIGNAGE_RUNTIME_DIR': str(runtime)}), patch('backend.app.desktop_session.os.geteuid', return_value=0):
                with self.assertRaisesRegex(RuntimeError, 'ohne sudo'):
                    with TestClient(create_app()):
                        pass
            self.assertFalse(runtime.exists())
