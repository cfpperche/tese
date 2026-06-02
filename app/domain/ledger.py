from app.db.repositories import LedgerRepository


def correct_event(
    repo: LedgerRepository,
    target_event_id: str,
    correction_id: str,
    date: str,
    reason: str,
) -> None:
    repo.correct_event(target_event_id, correction_id=correction_id, date=date, reason=reason)
