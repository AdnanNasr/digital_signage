from pathlib import Path

from python_project.main import VIDEO_EXTS

IMAGE_FORMATS = {".jpg": "JPEG", ".jpeg": "JPEG", ".png": "PNG", ".webp": "WEBP"}
MEDIA_EXTS = VIDEO_EXTS | IMAGE_FORMATS.keys()


def media_type(name: str) -> str:
    return "image" if Path(name).suffix.lower() in IMAGE_FORMATS else "video"
