"""Discover and configure the display in the backend user's desktop session."""
import json
import logging
import os
import re
import subprocess
import tempfile
import threading
from pathlib import Path

from fastapi import HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator
from typing import Literal

from ..desktop_session import desktop_environment

logger = logging.getLogger(__name__)
ROTATIONS = {0: 'normal', 90: 'left', 180: 'inverted', 270: 'right'}
WLR_ROTATIONS = {0: 'normal', 90: '90', 180: '180', 270: '270'}


class OrientationInput(BaseModel):
    model_config = ConfigDict(strict=True, extra='forbid')
    rotation: Literal[0, 90, 180, 270]
    fit_mode: Literal['contain', 'cover', 'stretch'] | None = None
    output: str | None = Field(default=None, min_length=1, max_length=200)

    @field_validator('rotation', mode='before')
    @classmethod
    def strict_rotation(cls, value):
        if type(value) is not int:
            raise ValueError('Rotation must be an integer')
        return value


class FitInput(BaseModel):
    model_config = ConfigDict(strict=True, extra='forbid')
    fit_mode: Literal['contain', 'cover', 'stretch']


class SavedDisplay(OrientationInput, FitInput):
    fit_mode: Literal['contain', 'cover', 'stretch']


class DisplayService:
    def __init__(self, settings, player):
        self.player = player
        self.path = settings.runtime_dir / 'display.json'
        self.saved = {'output': None, 'rotation': 0, 'fit_mode': 'contain'}
        if self.path.exists():
            try:
                self.saved = SavedDisplay.model_validate(json.loads(self.path.read_text())['display']).model_dump()
            except (ValueError, KeyError, TypeError) as error:
                raise RuntimeError('Die gespeicherten Bildschirmeinstellungen sind beschädigt. Bitte die Sicherung prüfen.') from error
        self.player.set_fit_mode(self.saved['fit_mode'])
        self._stop = threading.Event()
        self._thread = None
        self.restore_error = None

    @staticmethod
    def session():
        # Never use Xwayland's xrandr to configure physical Wayland outputs.
        environment = desktop_environment()
        if environment.get('WAYLAND_DISPLAY') or environment.get('XDG_SESSION_TYPE') == 'wayland':
            return 'wayland'
        if environment.get('DISPLAY'):
            return 'x11'
        return 'unsupported'

    @staticmethod
    def _run(args):
        try:
            result = subprocess.run(args, capture_output=True, text=True, timeout=5,
                                    env={**desktop_environment(), 'LC_ALL': 'C'}, check=False)
        except FileNotFoundError as error:
            raise HTTPException(503, f'{args[0]} ist nicht installiert.') from error
        except (OSError, subprocess.TimeoutExpired) as error:
            raise HTTPException(503, 'Der Bildschirm ist nicht erreichbar.') from error
        if result.returncode:
            raise HTTPException(503, 'Der Bildschirm ist nicht erreichbar. Bitte die Desktop-Sitzung und das Anzeigeprotokoll prüfen.')
        return result.stdout

    @staticmethod
    def parse_x11(text):
        outputs = []
        for line in text.splitlines():
            match = re.match(r'^(\S+) connected(?: primary)? (\d+)x(\d+)[+-]\d+[+-]\d+(.*)', line)
            if not match:
                continue
            name, width, height, tail = match.groups()
            # The actual rotation precedes the parenthesized capability list.
            current = tail.split('(')[0].strip().split()
            transform = next((v for v in current if v in ROTATIONS.values()), 'normal')
            capabilities = re.search(r'\(([^)]*)\)', tail)
            supported = [angle for angle, value in ROTATIONS.items()
                         if capabilities and value in capabilities[1].split()]
            outputs.append({'name': name, 'rotation': next(k for k, v in ROTATIONS.items() if v == transform),
                            'transform': transform, 'rotations': supported or [0],
                            'resolution': {'width': int(width), 'height': int(height)}})
        return outputs

    @staticmethod
    def parse_wayland(text):
        outputs = []
        for block in re.split(r'(?=^\S)', text, flags=re.M):
            if not block.strip() or not re.search(r'Enabled:\s+yes', block):
                continue
            name = block.split()[0]
            mode = re.search(r'(\d+)x(\d+) px[^\n]*\bcurrent\b', block)
            transform = re.search(r'Transform:\s+(\S+)', block)
            if not mode or not transform:
                continue
            value = transform[1]
            rotation = next((k for k, v in WLR_ROTATIONS.items() if v == value), None)
            width, height = int(mode[1]), int(mode[2])
            if value in ('90', '270', 'flipped-90', 'flipped-270'):
                width, height = height, width
            outputs.append({'name': name, 'rotation': rotation, 'transform': value,
                            'rotations': list(ROTATIONS) if rotation is not None else [],
                            'resolution': {'width': width, 'height': height}})
        return outputs

    def outputs(self):
        session = self.session()
        if session == 'wayland':
            return self.parse_wayland(self._run(['wlr-randr']))
        if session == 'x11':
            return self.parse_x11(self._run(['xrandr', '--query']))
        raise HTTPException(503, 'Keine erreichbare Desktop-Sitzung gefunden. Bitte den Server als Benutzer des angemeldeten Pi-Desktops starten und WAYLAND_DISPLAY sowie XDG_RUNTIME_DIR prüfen.')

    def _output(self, outputs, name=None):
        target = name or self.saved['output']
        if target:
            output = next((item for item in outputs if item['name'] == target), None)
            if output is None:
                raise HTTPException(503, 'Der Bildschirm ist nicht erreichbar.')
            return output
        if len(outputs) == 1:
            return outputs[0]
        if not outputs:
            raise HTTPException(503, 'Der Bildschirm ist nicht erreichbar.')
        raise HTTPException(409, 'Bitte den angeschlossenen Bildschirm auswählen.')

    def settings(self):
        with self.player.lock:
            error = None
            outputs = []
            output = None
            session = 'unsupported'
            try:
                session = self.session()
                outputs = self.outputs()
                output = self._output(outputs)
            except HTTPException as failure:
                error = failure.detail
            try:
                fit_mode = self.player.current_fit_mode()
            except Exception:
                fit_mode = 'unavailable'
                error = error or 'Der Player ist nicht erreichbar.'
            return {'output': output['name'] if output else None,
                    'rotation': output['rotation'] if output else None,
                    'resolution': output['resolution'] if output else None,
                    'fit_mode': fit_mode,
                    'session': session, 'available': output is not None,
                    'outputs': outputs, 'saved': dict(self.saved),
                    'error': error or self.restore_error}

    def _rotate(self, output, transform):
        if os.geteuid() == 0:
            raise HTTPException(403, 'Bitte den Server als Benutzer der Desktop-Sitzung starten, nicht als root.')
        if self.session() == 'wayland':
            self._run(['wlr-randr', '--output', output, '--transform', transform])
        elif self.session() == 'x11':
            self._run(['xrandr', '--output', output, '--rotate', transform])
        else:
            raise HTTPException(503, 'Der Bildschirm ist nicht erreichbar.')

    def _persist(self, value):
        temporary = tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=self.path.parent,
                                               prefix='.display-', delete=False)
        try:
            with temporary:
                json.dump({'display': value}, temporary)
                temporary.flush()
                os.fsync(temporary.fileno())
            os.replace(temporary.name, self.path)
            self.saved = value
        finally:
            Path(temporary.name).unlink(missing_ok=True)

    def apply(self, rotation=None, fit_mode=None, output=None, persist=True):
        with self.player.lock:
            before = None
            old_fit = self.player.fit_mode
            target = None
            attempted = False
            try:
                if rotation is not None:
                    before = self._output(self.outputs(), output)
                    if rotation not in before['rotations']:
                        raise HTTPException(422, 'Diese Bildschirmausrichtung wird nicht unterstützt.')
                    target = before['name']
                    if before['rotation'] != rotation:
                        attempted = True
                        transform = (WLR_ROTATIONS if self.session() == 'wayland' else ROTATIONS)[rotation]
                        self._rotate(target, transform)
                        actual = self._output(self.outputs(), target)
                        if actual['rotation'] != rotation:
                            raise HTTPException(503, 'Die Einstellungen konnten nicht übernommen werden.')
                if fit_mode is not None:
                    self.player.set_fit_mode(fit_mode)
                value = {**self.saved, 'fit_mode': self.player.fit_mode}
                if rotation is not None:
                    value.update(output=target, rotation=rotation)
                if persist:
                    self._persist(value)
                self.restore_error = None
            except Exception as error:
                failures = []
                try:
                    if self.player.fit_mode != old_fit:
                        self.player.set_fit_mode(old_fit)
                except Exception:
                    failures.append('Darstellung')
                if attempted:
                    try:
                        self._rotate(target, before['transform'])
                        restored = self._output(self.outputs(), target)
                        if restored['transform'] != before['transform']:
                            raise RuntimeError('Rotation rollback did not take effect')
                    except Exception:
                        failures.append('Ausrichtung')
                if failures:
                    self.restore_error = 'Vorherige Einstellungen konnten nicht wiederhergestellt werden. Bitte den Bildschirm prüfen.'
                    logger.exception('Display rollback failed: %s', failures)
                    raise HTTPException(503, self.restore_error) from error
                raise
            return self.settings() if persist else None

    def reset(self, output=None):
        return self.apply(rotation=0, fit_mode='contain', output=output)

    def start(self):
        # Retry after desktop readiness and hotplug. Never switch to another output.
        self._thread = threading.Thread(target=self._restore, name='display-restore', daemon=True)
        self._thread.start()

    def _restore(self):
        while not self._stop.is_set():
            try:
                with self.player.lock:
                    if self.saved['output'] is not None:
                        self.apply(rotation=self.saved['rotation'], persist=False)
            except Exception as error:
                message = error.detail if isinstance(error, HTTPException) else 'Die Bildschirmeinstellungen konnten nicht wiederhergestellt werden.'
                if message != self.restore_error:
                    logger.warning('Display restore pending: %s', message)
                self.restore_error = message
            self._stop.wait(5)

    def close(self):
        self._stop.set()
        if self._thread:
            self._thread.join()
