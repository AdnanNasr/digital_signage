from fastapi import APIRouter, HTTPException, Request, Response

from ..models.playlist import PlaylistInput, PlaylistSelection

router = APIRouter(prefix="/api/playlists", tags=["Wiedergabelisten"])


@router.get("")
def list_playlists(request: Request):
    return request.app.state.playlists.list()


@router.post("", status_code=201)
def create(data: PlaylistInput, request: Request):
    return request.app.state.playlists.create(data)


@router.put("/selected")
def select(data: PlaylistSelection, request: Request):
    return request.app.state.playlists.select(data.id)


@router.put("/{playlist_id}")
def update(playlist_id: str, data: PlaylistInput, request: Request):
    return request.app.state.playlists.update(playlist_id, data)


@router.delete("/{playlist_id}", status_code=204)
def delete(playlist_id: str, request: Request, confirm: bool = False):
    if not confirm:
        raise HTTPException(400, "Bitte das Löschen bestätigen.")
    request.app.state.playlists.delete(playlist_id)
    return Response(status_code=204)


@router.post("/{playlist_id}/start")
def start(playlist_id: str, request: Request):
    return request.app.state.playlists.start(playlist_id)
