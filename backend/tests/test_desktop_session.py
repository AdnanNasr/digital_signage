import os
import socket
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from fastapi import HTTPException

from backend.app.desktop_session import desktop_environment
from backend.app.services.display import DisplayService
from backend.app.services.player import PlayerService
from backend.app.config import Settings


class DesktopSessionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sg-session-', dir='/tmp')
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.environment = self.enterContext(patch.dict(os.environ, {
            'XDG_RUNTIME_DIR': str(self.directory), 'XDG_SESSION_TYPE': 'tty',
        }, clear=True))

    def listen(self, name):
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.addCleanup(listener.close)
        listener.bind(str(self.directory / name))
        listener.listen(32)
        return listener

    def test_ssh_discovers_actual_socket_and_passes_environment_to_tool(self):
        self.listen('wayland-3')
        environment = desktop_environment()
        self.assertEqual(environment['WAYLAND_DISPLAY'], 'wayland-3')
        self.assertEqual(environment['XDG_SESSION_TYPE'], 'wayland')
        self.assertEqual(environment['XDG_RUNTIME_DIR'], str(self.directory))
        self.assertNotIn('WAYLAND_DISPLAY', os.environ)
        self.assertEqual(DisplayService.session(), 'wayland')
        with patch('backend.app.services.display.subprocess.run', return_value=Mock(returncode=0, stdout='outputs')) as run:
            self.assertEqual(DisplayService._run(['wlr-randr']), 'outputs')
            self.assertEqual(run.call_args.kwargs['env']['WAYLAND_DISPLAY'], 'wayland-3')
            self.assertEqual(run.call_args.kwargs['env']['XDG_RUNTIME_DIR'], str(self.directory))

    def test_explicit_selection_is_preserved_with_multiple_compositors(self):
        self.listen('wayland-1')
        self.listen('wayland-4')
        os.environ['WAYLAND_DISPLAY'] = 'wayland-4'
        self.assertEqual(desktop_environment()['WAYLAND_DISPLAY'], 'wayland-4')
        os.environ['WAYLAND_DISPLAY'] = str(self.directory / 'wayland-4')
        self.assertEqual(desktop_environment()['WAYLAND_DISPLAY'], str(self.directory / 'wayland-4'))

    def test_multiple_live_sockets_require_selection(self):
        self.listen('wayland-1')
        self.listen('wayland-4')
        with self.assertRaises(HTTPException) as error:
            desktop_environment()
        self.assertIn('Mehrere Wayland-Sitzungen', error.exception.detail)

    def test_stale_files_locks_and_symlinks_are_ignored(self):
        stale = self.listen('wayland-0')
        stale.close()
        (self.directory / 'wayland-1.lock').touch()
        (self.directory / 'wayland-fake').touch()
        self.listen('wayland-2')
        (self.directory / 'wayland-link').symlink_to(self.directory / 'wayland-2')
        self.assertEqual(desktop_environment()['WAYLAND_DISPLAY'], 'wayland-2')

    def test_root_and_other_users_runtime_are_not_discovered(self):
        self.listen('wayland-1')
        for uid in (0, os.geteuid() + 1):
            with patch('backend.app.desktop_session.os.geteuid', return_value=uid):
                self.assertNotIn('WAYLAND_DISPLAY', desktop_environment())
        self.directory.chmod(0o755)
        self.assertNotIn('WAYLAND_DISPLAY', desktop_environment())

    def test_display_environment_and_explicit_x11_are_respected(self):
        os.environ['DISPLAY'] = ':9'
        self.listen('wayland-1')
        self.assertEqual(DisplayService.session(), 'x11')
        self.assertNotIn('WAYLAND_DISPLAY', desktop_environment())
        os.environ['XDG_SESSION_TYPE'] = 'wayland'
        self.assertEqual(DisplayService.session(), 'wayland')
        self.assertEqual(desktop_environment()['WAYLAND_DISPLAY'], 'wayland-1')

    def test_no_socket_and_late_desktop_start(self):
        self.assertEqual(DisplayService.session(), 'unsupported')
        self.listen('wayland-5')
        self.assertEqual(DisplayService.session(), 'wayland')

    def test_default_runtime_directory_uses_current_uid(self):
        del os.environ['XDG_RUNTIME_DIR']
        fake_directory = Mock()
        fake_directory.lstat.return_value = self.directory.stat()
        fake_directory.glob.return_value = []
        with patch('backend.app.desktop_session.Path', return_value=fake_directory) as constructor:
            desktop_environment()
            constructor.assert_called_once_with(f'/run/user/{os.geteuid()}')

    def test_mpv_uses_same_discovered_session(self):
        self.listen('wayland-7')
        settings = Settings(self.directory / 'media', self.directory / 'run', 'test-token-123')
        player = PlayerService(settings)
        player.open()
        self.addCleanup(player.close)
        with patch('backend.app.services.player.subprocess.Popen') as popen, patch.object(player, '_command', return_value=True):
            popen.return_value.poll.return_value = None
            player._ensure_running()
            environment = popen.call_args.kwargs['env']
            self.assertEqual(environment['WAYLAND_DISPLAY'], 'wayland-7')
            self.assertEqual(environment['XDG_RUNTIME_DIR'], str(self.directory))
