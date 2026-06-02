from typing import Protocol

from app.domain.models import Quote


class MarketDataSource(Protocol):
    def quotes(self, tickers: list[str]) -> list[Quote]:
        """Return normalized quote snapshots for tickers."""
