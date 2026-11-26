from fastapi import APIRouter, HTTPException, Query, Request, Response

router = APIRouter(prefix="/api/media", tags=["Medienverwaltung"])


@router.get("")
def list_media(request: Request):
    return request.app.state.media.list()


@router.post("/upload", status_code=201)
async def upload(request: Request, filename: str = Query(...)):
    length = request.headers.get("content-length")
    if length is not None:
        try:
            declared_size = int(length)
        except ValueError:
            raise HTTPException(400, "Ungültige Dateigröße.")
        if declared_size < 0:
            raise HTTPException(400, "Ungültige Dateigröße.")
        if declared_size > request.app.state.settings.max_upload_bytes:
            raise HTTPException(413, "Die Datei überschreitet die erlaubte Größe.")
    return await request.app.state.media.upload(filename, request.stream())


@router.get("/{media_id}")
def get_media(media_id: str, request: Request):
    return request.app.state.media.get(media_id)


@router.get("/{media_id}/preview")
def preview(media_id: str, request: Request):
    return Response(content=request.app.state.media.preview(media_id), media_type="image/png",
                        headers={"Cache-Control": "private, max-age=60"})


@router.delete("/{media_id}", status_code=204)
def delete_media(media_id: str, request: Request, confirm: bool = False):
    if not confirm:
        raise HTTPException(400, "Bitte das Löschen bestätigen.")
    request.app.state.media.delete(media_id)
    return Response(status_code=204)
