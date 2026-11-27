import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from backend.app.config import Settings
from backend.app.services.player import PlayerError, PlayerService


class PlayerOutputTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='sg-output-', dir='/tmp')
        self.addCleanup(self.temp.cleanup)
        directory = Path(self.temp.name)
        self.player = PlayerService(Settings(directory / 'media', directory / 'run', 'test-password-123'))
        self.player.open()
        self.addCleanup(self.player.close)

    def test_linux_wayland_uses_compositor_output_even_with_xwayland_display(self):
        environment = {'WAYLAND_DISPLAY': 'wayland-5', 'XDG_RUNTIME_DIR': '/run/user/1000',
                       'DISPLAY': ':0', 'XDG_SESSION_TYPE': 'tty'}
        with patch('backend.app.services.player.sys.platform', 'linux'), patch('backend.app.services.player.desktop_environment', return_value=environment), patch('backend.app.services.player.subprocess.Popen') as popen, patch.object(self.player, '_command', return_value=True):
            popen.return_value.poll.return_value = None
            self.player._ensure_running()
            command = popen.call_args.args[0]
            self.assertIn('--vo=gpu', command)
            self.assertIn('--gpu-api=opengl', command)
            self.assertIn('--gpu-context=wayland', command)
            self.assertNotIn('--gpu-context=auto', command)
            self.assertNotIn('--gpu-context=drm', command)
            self.assertIn('--input-terminal=no', command)
            self.assertIn('--msg-level=all=warn', command)
            self.assertNotIn('--no-terminal', command)
            self.assertEqual(popen.call_args.kwargs['env'], environment)
            self.player._ensure_running()
            self.assertEqual(popen.call_count, 1)

    def test_other_platforms_and_explicit_x11_keep_existing_output_selection(self):
        with patch('backend.app.services.player.sys.platform', 'darwin'):
            self.assertEqual(self.player._video_output_options({'WAYLAND_DISPLAY': 'wayland-0'}), [])
        with patch('backend.app.services.player.sys.platform', 'linux'):
            self.assertEqual(self.player._video_output_options({'DISPLAY': ':0', 'XDG_SESSION_TYPE': 'x11'}), [])
            self.assertEqual(self.player._video_output_options({}), [])
            self.assertIn('--gpu-context=wayland', self.player._video_output_options({'XDG_SESSION_TYPE': 'wayland'}))

    def test_wayland_initialization_failure_cleans_up_without_drm_retry(self):
        process = Mock()
        process.poll.return_value = 1
        environment = {'WAYLAND_DISPLAY': 'wayland-2'}
        with patch('backend.app.services.player.sys.platform', 'linux'), patch('backend.app.services.player.desktop_environment', return_value=environment), patch('backend.app.services.player.subprocess.Popen', return_value=process) as popen:
            with self.assertRaisesRegex(PlayerError, 'Wayland-Fenster'):
                self.player._ensure_running()
            self.assertEqual(popen.call_count, 1)
            self.assertIsNone(self.player._process)
            self.assertFalse(self.player.socket_path.exists())
