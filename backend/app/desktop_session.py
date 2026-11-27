"""Resolve a local Wayland session when started from SSH as its desktop user."""
import os
import socket
import stat
from pathlib import Path

from fastapi import HTTPException


def require_desktop_user() -> None:
    if os.geteuid() == 0:
        raise RuntimeError(
            'Der Server darf nicht als root laufen. Bitte ohne sudo als Benutzer '
            'des angemeldeten Pi-Desktops starten: backend/.venv/bin/python backend/run.py. '
            'Falls Dateien zuvor mit sudo erstellt wurden, muss ihr Besitzer zuerst '
            'auf den Desktop-Benutzer korrigiert werden.'
        )


def _runtime_directory() -> Path | None:
    uid = os.geteuid()
    if uid == 0:
        return None
    directory = Path(os.environ.get('XDG_RUNTIME_DIR') or f'/run/user/{uid}')
    try:
        info = directory.lstat()
        if stat.S_ISDIR(info.st_mode) and info.st_uid == uid and info.st_mode & 0o077 == 0:
            return directory
    except OSError:
        pass
    return None


def _active_wayland_sockets(directory: Path) -> list[Path]:
    sockets = []
    for candidate in directory.glob('wayland-*'):
        try:
            info = candidate.lstat()
            if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.geteuid():
                continue
            # Socket files can survive a crashed compositor; only use live listeners.
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
                connection.settimeout(0.2)
                connection.connect(str(candidate))
            sockets.append(candidate)
        except OSError:
            continue
    return sorted(sockets)


def desktop_environment() -> dict[str, str]:
    environment = dict(os.environ)
    if environment.get('WAYLAND_DISPLAY'):
        # Preserve explicit selections, including absolute socket paths.
        if not environment.get('XDG_RUNTIME_DIR'):
            directory = _runtime_directory()
            if directory is not None:
                environment['XDG_RUNTIME_DIR'] = str(directory)
        return environment
    # Respect an explicit X11 session and forwarded SSH X displays. A Wayland
    # session hint takes precedence over DISPLAY, which may belong to Xwayland.
    if environment.get('DISPLAY') and environment.get('XDG_SESSION_TYPE') != 'wayland':
        return environment
    directory = _runtime_directory()
    if directory is None:
        return environment
    sockets = _active_wayland_sockets(directory)
    if len(sockets) > 1:
        raise HTTPException(503, 'Mehrere Wayland-Sitzungen gefunden. Bitte WAYLAND_DISPLAY für den Server ausdrücklich festlegen.')
    if sockets:
        environment.update(XDG_RUNTIME_DIR=str(directory), WAYLAND_DISPLAY=sockets[0].name,
                           XDG_SESSION_TYPE='wayland')
    return environment
