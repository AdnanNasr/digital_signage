from fastapi import APIRouter, Request

from ..services.display import FitInput, OrientationInput

router = APIRouter(prefix='/api/display', tags=['Bildschirmeinstellungen'])


@router.get('/settings')
def settings(request: Request):
    return request.app.state.display.settings()


@router.get('/outputs')
def outputs(request: Request):
    return request.app.state.display.outputs()


@router.put('/orientation')
def orientation(data: OrientationInput, request: Request):
    return request.app.state.display.apply(rotation=data.rotation, output=data.output, fit_mode=data.fit_mode)


@router.put('/fit-mode')
def fit_mode(data: FitInput, request: Request):
    return request.app.state.display.apply(fit_mode=data.fit_mode)


@router.post('/reset')
def reset(request: Request, data: OrientationInput | None = None):
    return request.app.state.display.reset(output=data.output if data else None)
