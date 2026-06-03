from typing import Any

from fastapi import APIRouter, HTTPException

from app.api.deps import ConnDep
from app.db.repositories import LedgerRepository

router = APIRouter(prefix="/api/ledger", tags=["ledger"])


@router.get("/events")
def list_events(conn: ConnDep):
    return LedgerRepository(conn).list_events()


@router.post("/events")
def create_event(payload: dict[str, Any], conn: ConnDep):
    repo = LedgerRepository(conn)
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
def correct_event(event_id: str, payload: dict[str, Any], conn: ConnDep):
    repo = LedgerRepository(conn)
    repo.correct_event(
        event_id,
        correction_id=payload["correction_id"],
        date=payload["date"],
        reason=payload["reason"],
    )
    return {"ok": True}
