import json
from unittest.mock import patch

from fastapi import HTTPException
from test_player_api import ApiFixture, headless_mpv
from backend.app.services.display import DisplayService


class DisplayTests(ApiFixture):
    def setUp(self):
        super().setUp()
        self.display = self.client.app.state.display
        self.rotation = 0
        self.connected = True
        self.outputs_patch = patch.object(self.display, 'outputs', side_effect=self.outputs)
        self.outputs_patch.start()
        self.addCleanup(self.outputs_patch.stop)
        self.rotate_patch = patch.object(self.display, '_rotate', side_effect=self.rotate)
        self.rotator = self.rotate_patch.start()
        self.addCleanup(self.rotate_patch.stop)
        self.enterContext(patch.object(self.display, 'session', return_value='wayland'))
        # Stop the worker before removing the simulated display adapters.
        self.addCleanup(self.display.close)

    def outputs(self):
        if not self.connected:
            return []
        return [{'name': 'DP-2', 'rotation': self.rotation,
                 'transform': 'normal' if self.rotation == 0 else str(self.rotation),
                 'rotations': [0, 90, 180, 270],
                 'resolution': {'width': 1080 if self.rotation % 180 else 1920,
                                'height': 1920 if self.rotation % 180 else 1080}}]

    def rotate(self, output, transform):
        self.assertEqual(output, 'DP-2')
        self.rotation = 0 if transform == 'normal' else int(transform)

    def test_actual_orientation_save_reset_and_validation(self):
        self.rotation = 180
        self.assertEqual(self.client.get('/api/display/settings').json()['rotation'], 180)
        response = self.client.put('/api/display/orientation', json={'rotation': 90, 'fit_mode': 'cover'})
        self.assertEqual(response.status_code, 200, response.text)
        self.assertTrue(self.display._thread.is_alive())
        self.assertEqual(response.json()['resolution'], {'width': 1080, 'height': 1920})
        stored = json.loads(self.display.path.read_text())['display']
        self.assertEqual(stored, {'rotation': 90, 'output': 'DP-2', 'fit_mode': 'cover'})
        for value in (45, '90', True, 90.0, None):
            self.assertEqual(self.client.put('/api/display/orientation', json={'rotation': value}).status_code, 422)
        self.assertEqual(self.client.put('/api/display/fit-mode', json={'fit_mode': 'zoom'}).status_code, 422)
        self.assertEqual(self.client.post('/api/display/reset').status_code, 200)
        self.assertEqual(self.rotation, 0)
        self.assertEqual(self.display.saved['fit_mode'], 'contain')

    def test_authentication_all_endpoints(self):
        del self.client.headers['Authorization']
        for method, path, body in [('GET', 'settings', None), ('GET', 'outputs', None),
                                   ('PUT', 'orientation', {'rotation': 90}),
                                   ('PUT', 'fit-mode', {'fit_mode': 'cover'}), ('POST', 'reset', None)]:
            self.assertEqual(self.client.request(method, '/api/display/'+path, json=body).status_code, 401)

    def test_failed_save_rolls_back_and_preserves_saved_file(self):
        self.client.put('/api/display/orientation', json={'rotation': 90})
        previous = self.display.path.read_bytes()
        with patch.object(self.display, '_persist', side_effect=OSError('disk failed')):
            response = self.client.put('/api/display/orientation', json={'rotation': 270, 'fit_mode': 'stretch'})
        self.assertEqual(response.status_code, 500)
        self.assertEqual(self.rotation, 90)
        self.assertEqual(self.display.player.fit_mode, 'contain')
        self.assertEqual(self.display.path.read_bytes(), previous)

    def test_command_failure_and_disconnection_do_not_save(self):
        self.rotator.side_effect = HTTPException(503, 'Der Bildschirm ist nicht erreichbar.')
        self.assertEqual(self.client.put('/api/display/orientation', json={'rotation': 90}).status_code, 503)
        self.assertFalse(self.display.path.exists())
        self.connected = False
        settings = self.client.get('/api/display/settings').json()
        self.assertIsNone(settings['rotation'])
        self.assertFalse(settings['available'])
        self.assertEqual(self.client.put('/api/display/orientation', json={'rotation': 90}).status_code, 503)

    def test_saved_restore_waits_for_output_and_hotplug(self):
        self.client.put('/api/display/orientation', json={'rotation': 270, 'fit_mode': 'stretch'})
        restored = DisplayService(self.settings, self.display.player)
        self.assertEqual(restored.saved['rotation'], 270)
        self.assertEqual(restored.player.fit_mode, 'stretch')
        self.rotation = 0
        restored.outputs = self.outputs
        restored._rotate = self.rotate
        restored.session = lambda: 'wayland'
        restored._stop.wait = lambda delay: restored._stop.set()
        restored._restore()
        self.assertEqual(self.rotation, 270)
        self.connected = False
        restored._stop.clear()
        restored._restore()
        self.assertIsNotNone(restored.restore_error)
        self.connected = True
        self.rotation = 0
        restored._stop.clear()
        restored._restore()
        self.assertEqual(self.rotation, 270)
        self.assertIsNone(restored.restore_error)

    def test_parsers_and_session_no_xwayland_fallback(self):
        x11 = 'HDMI-2 connected primary 1080x1920+0+0 left (normal left inverted right x axis y axis) 500mm x 300mm\nHDMI-1 disconnected (normal left inverted right)'
        result = DisplayService.parse_x11(x11)
        self.assertEqual(result[0]['rotation'], 90)
        self.assertEqual(result[0]['rotations'], [0, 90, 180, 270])
        self.assertEqual(len(result), 1)
        wayland = 'DP-2 "Screen"\n  Enabled: yes\n  Modes:\n    1920x1080 px, 60 Hz (preferred, current)\n  Transform: 270\n  Scale: 1\nHDMI-A-1 "Off"\n  Enabled: no\n'
        result = DisplayService.parse_wayland(wayland)
        self.assertEqual(result[0]['rotation'], 270)
        self.assertEqual(result[0]['resolution'], {'width': 1080, 'height': 1920})
        self.assertEqual(len(result), 1)

    def test_fit_changes_real_mpv_without_restarting_or_unpausing(self):
        from PIL import Image
        Image.new('RGB', (90, 160)).save(self.videos / 'portrait.png')
        player = self.display.player
        with patch('backend.app.services.player.subprocess.Popen', side_effect=headless_mpv):
            self.assertEqual(self.client.post('/api/player/start').status_code, 200)
            process = player._process
            self.client.post('/api/player/pause')
            for mode, aspect, scan in [('cover', True, 1), ('stretch', False, 0), ('contain', True, 0)]:
                response = self.client.put('/api/display/fit-mode', json={'fit_mode': mode})
                self.assertEqual(response.status_code, 200, response.text)
                self.assertEqual(player._command('get_property', 'keepaspect'), aspect)
                self.assertEqual(player._command('get_property', 'panscan'), scan)
                self.assertTrue(player._command('get_property', 'pause'))
                self.assertIs(player._process, process)
            self.client.put('/api/display/fit-mode', json={'fit_mode': 'stretch'})
            self.client.post('/api/player/restart')
            self.assertFalse(player._command('get_property', 'keepaspect'))

    def test_rotation_while_playing_and_paused_preserves_process_and_state(self):
        from PIL import Image
        import subprocess
        Image.new('RGB', (160, 90)).save(self.videos / 'landscape.png')
        Image.new('RGB', (90, 160)).save(self.videos / 'portrait.png')
        for name, size in [('landscape', '160x90'), ('portrait', '90x160')]:
            subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i',
                            f'color=c=black:s={size}:r=2', '-t', '30', '-c:v', 'mpeg4',
                            str(self.videos / f'{name}.mp4')], check=True, capture_output=True)
        player = self.display.player
        with patch('backend.app.services.player.subprocess.Popen', side_effect=headless_mpv):
            self.assertEqual(self.client.post('/api/player/start').status_code, 200)
            process = player._process
            for index in range(4):
                for paused in [False, True]:
                    self.client.post('/api/player/pause' if paused else '/api/player/resume')
                    response = self.client.put('/api/display/orientation', json={'rotation': 90 if paused else 270, 'fit_mode': 'cover'})
                    self.assertEqual(response.status_code, 200, response.text)
                    self.assertEqual(player._command('get_property', 'pause'), paused)
                    self.assertIs(player._process, process)
                    self.assertEqual(player._command('get_property', 'video-rotate'), 0)
                self.client.post('/api/player/next')

    def test_commands_use_session_tools_and_argument_lists(self):
        import os
        import subprocess
        from unittest.mock import Mock
        with patch.dict(os.environ, {'WAYLAND_DISPLAY': 'wayland-1', 'DISPLAY': ':0', 'XDG_SESSION_TYPE': 'wayland'}):
            self.assertEqual(DisplayService.session(), 'wayland')
        with patch.dict(os.environ, {'DISPLAY': ':0', 'XDG_SESSION_TYPE': 'x11'}, clear=True):
            self.assertEqual(DisplayService.session(), 'x11')
        with patch('backend.app.services.display.subprocess.run', return_value=Mock(returncode=0, stdout='')) as run:
            DisplayService._run(['wlr-randr', '--output', 'DP-2', '--transform', '90'])
            self.assertEqual(run.call_args.args[0], ['wlr-randr', '--output', 'DP-2', '--transform', '90'])
            self.assertNotIn('shell', run.call_args.kwargs)
        for failure in [FileNotFoundError(), subprocess.TimeoutExpired('wlr-randr', 5)]:
            with patch('backend.app.services.display.subprocess.run', side_effect=failure):
                with self.assertRaises(HTTPException):
                    DisplayService._run(['wlr-randr'])

    def test_multiple_outputs_require_explicit_selection(self):
        outputs = self.outputs()
        outputs.append({**outputs[0], 'name': 'HDMI-A-2'})
        with patch.object(self.display, 'outputs', return_value=outputs):
            response = self.client.put('/api/display/orientation', json={'rotation': 0})
            self.assertEqual(response.status_code, 409)
            response = self.client.put('/api/display/orientation', json={'rotation': 0, 'output': 'HDMI-A-2'})
            self.assertEqual(response.status_code, 200)
            self.assertEqual(self.display.saved['output'], 'HDMI-A-2')

    def test_successful_command_without_actual_change_is_rolled_back(self):
        def incorrect(output, transform):
            self.rotation = 180 if transform == '90' else 0
        self.rotator.side_effect = incorrect
        response = self.client.put('/api/display/orientation', json={'rotation': 90})
        self.assertEqual(response.status_code, 503)
        self.assertEqual(self.rotation, 0)
        self.assertFalse(self.display.path.exists())

    def test_os_rotation_rejects_root(self):
        with patch('backend.app.services.display.os.geteuid', return_value=0):
            with self.assertRaises(HTTPException) as error:
                DisplayService._rotate(self.display, 'DP-2', '90')
            self.assertEqual(error.exception.status_code, 403)
