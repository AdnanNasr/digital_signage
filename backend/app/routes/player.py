from fastapi import APIRouter, Request

router = APIRouter(prefix="/api/player", tags=["Wiedergabe"])


@router.get("/status")
def status(request: Request):
    return request.app.state.player.status()


@router.post("/start")
def start(request: Request):
    return request.app.state.player.start()


@router.post("/pause")
def pause(request: Request):
    return request.app.state.player.pause()


@router.post("/resume")
def resume(request: Request):
    return request.app.state.player.resume()


@router.post("/stop")
def stop(request: Request):
    return request.app.state.player.stop()


@router.post("/next")
def next_file(request: Request):
    return request.app.state.player.next()


@router.post("/previous")
def previous(request: Request):
    return request.app.state.player.previous()


@router.post("/restart")
def restart(request: Request):
    return request.app.state.player.restart()
