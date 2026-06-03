from fastapi import APIRouter

from app.api.deps import ConnDep
from app.domain.derivations import dashboard_projection

router = APIRouter(prefix="/api", tags=["dashboard"])


@router.get("/dashboard")
def dashboard(conn: ConnDep):
    return dashboard_projection(conn)
