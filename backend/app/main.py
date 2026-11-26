import errno
import logging
import secrets
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import Settings, get_allowed_origins
from .routes.player import router
from .routes.media import router as media_router
from .services.media import MediaService
from .services.player import PlayerError, PlayerService

bearer = HTTPBearer(auto_error=False)


def create_app(settings: Settings | None = None) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.settings = settings or Settings.from_env()
        player = PlayerService(app.state.settings)
        player.open()
        app.state.player = player
        app.state.media = MediaService(app.state.settings, player)
        try:
            yield
        finally:
            player.close()

    app = FastAPI(title="Digital Signage", version="0.1.0", lifespan=lifespan)
    # CORS settings do not require loading or creating the API token at import time.
    origins = settings.allowed_origins if settings else get_allowed_origins()
    app.add_middleware(CORSMiddleware, allow_origins=list(origins),
                       allow_methods=["GET", "POST", "DELETE"],
                       allow_headers=["Authorization", "Content-Type"])

    def authorize(request: Request, credentials: HTTPAuthorizationCredentials | None = Depends(bearer)):
        if credentials is None or not secrets.compare_digest(
            credentials.credentials.encode(), request.app.state.settings.api_token.encode()
        ):
            raise HTTPException(401, "Anmeldung erforderlich.", headers={"WWW-Authenticate": "Bearer"})

    @app.exception_handler(PlayerError)
    async def player_error(request: Request, error: PlayerError):
        return JSONResponse(status_code=error.status_code, content={"detail": str(error)})

    @app.get("/api/health", tags=["System"])
    def health():
        return {"status": "ok"}

    @app.exception_handler(OSError)
    async def storage_error(request: Request, error: OSError):
        logging.getLogger(__name__).exception("File operation failed", exc_info=error)
        full = error.errno in {errno.ENOSPC, errno.EDQUOT}
        return JSONResponse(
            status_code=507 if full else 500,
            content={"detail": "Nicht genügend Speicherplatz." if full else "Dateizugriff fehlgeschlagen."},
        )

    app.include_router(router, dependencies=[Depends(authorize)])
    app.include_router(media_router, dependencies=[Depends(authorize)])
    return app


app = create_app()
