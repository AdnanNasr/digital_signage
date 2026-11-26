import secrets
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .config import Settings
from .routes.player import router
from .services.player import PlayerError, PlayerService

bearer = HTTPBearer(auto_error=False)


def create_app(settings: Settings | None = None) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        app.state.settings = settings or Settings.from_env()
        player = PlayerService(app.state.settings)
        player.open()
        app.state.player = player
        try:
            yield
        finally:
            player.close()

    app = FastAPI(title="Digital Signage", version="0.1.0", lifespan=lifespan)

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

    app.include_router(router, dependencies=[Depends(authorize)])
    return app


app = create_app()
