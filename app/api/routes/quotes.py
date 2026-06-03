from fastapi import APIRouter, Request

from app.adapters.market.collector import refresh_quotes
from app.api.deps import ConnDep
from app.db.repositories import LedgerRepository

router = APIRouter(prefix="/api/quotes", tags=["quotes"])


@router.get("")
def list_quotes(conn: ConnDep):
    return LedgerRepository(conn).list_quotes()


@router.post("/refresh")
def refresh(request: Request, conn: ConnDep):
    repo = LedgerRepository(conn)
    return refresh_quotes(
        repo,
        request.app.state.market_data_source,
        request.app.state.watchlist_path,
    )
