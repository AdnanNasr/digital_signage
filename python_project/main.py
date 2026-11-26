import subprocess
import sys
from pathlib import Path

VIDEO_EXTS = {".mp4", ".mkv", ".mov", ".webm"}


def get_path() -> Path:
    return Path(__file__).resolve().parent / "videos"


def get_videos(videos_path: Path) -> list[Path]:
    if not videos_path.is_dir():
        return []
    return sorted(p for p in videos_path.iterdir()
                  if p.is_file() and p.suffix.lower() in VIDEO_EXTS)


def play_videos(videos: list[Path]) -> int:
    cmd = ["mpv", "--fullscreen", "--loop-playlist=inf", "--no-audio",
           *map(str, videos)]
    return subprocess.run(cmd).returncode


def main() -> int:
    videos_path = get_path()
    videos = get_videos(videos_path)
    if not videos:
        print(f"No videos found in {videos_path}", file=sys.stderr)
        return 1
    return play_videos(videos)


if __name__ == "__main__":
    sys.exit(main())