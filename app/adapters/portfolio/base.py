from typing import Protocol

from app.db.repositories import LedgerRepository


class PortfolioSource(Protocol):
    def ingest(self, repo: LedgerRepository) -> None:
        """Ingest portfolio source data as append-only ledger events."""
