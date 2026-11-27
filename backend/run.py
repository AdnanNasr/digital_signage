"""Start the API using its full package name, independent of the working directory."""

import argparse
import sys
from pathlib import Path

import uvicorn


def main() -> None:
    parser = argparse.ArgumentParser(description="Digital-Signage-Server starten.")
    parser.add_argument("--port", type=int, default=8000, help="Lokaler Server-Port.")
    args = parser.parse_args()
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from backend.app.desktop_session import require_desktop_user
    try:
        require_desktop_user()
    except RuntimeError as error:
        raise SystemExit(str(error)) from None
    uvicorn.run("backend.app.main:app", host="127.0.0.1", port=args.port, workers=1)


if __name__ == "__main__":
    main()
