from fastapi import APIRouter, Request

from app.adapters.market.collector import refresh_quotes
from app.db.repositories import LedgerRepository

router = APIRouter(prefix="/api/quotes", tags=["quotes"])


@router.get("")
def list_quotes(request: Request):
    return LedgerRepository(request.app.state.conn).list_quotes()


@router.post("/refresh")
def refresh(request: Request):
    repo = LedgerRepository(request.app.state.conn)
    return refresh_quotes(
        repo,
        request.app.state.market_data_source,
        request.app.state.watchlist_path,
    )
