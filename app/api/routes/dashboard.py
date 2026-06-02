from fastapi import APIRouter, Request

from app.domain.derivations import dashboard_projection

router = APIRouter(prefix="/api", tags=["dashboard"])


@router.get("/dashboard")
def dashboard(request: Request):
    return dashboard_projection(request.app.state.conn)
