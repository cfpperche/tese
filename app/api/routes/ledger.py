from typing import Any

from fastapi import APIRouter, HTTPException, Request

from app.db.repositories import LedgerRepository

router = APIRouter(prefix="/api/ledger", tags=["ledger"])


@router.get("/events")
def list_events(request: Request):
    return LedgerRepository(request.app.state.conn).list_events()


@router.post("/events")
def create_event(payload: dict[str, Any], request: Request):
    repo = LedgerRepository(request.app.state.conn)
    event_type = payload.pop("event_type")
    try:
        getattr(repo, f"add_{event_type}")(**payload)
    except AttributeError as exc:
        raise HTTPException(
            status_code=400,
            detail=f"unsupported event_type: {event_type}",
        ) from exc
    return {"ok": True}


@router.post("/events/{event_id}/correct")
def correct_event(event_id: str, payload: dict[str, Any], request: Request):
    repo = LedgerRepository(request.app.state.conn)
    repo.correct_event(
        event_id,
        correction_id=payload["correction_id"],
        date=payload["date"],
        reason=payload["reason"],
    )
    return {"ok": True}
