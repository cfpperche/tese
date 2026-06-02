from fastapi.testclient import TestClient

from app.db.repositories import LedgerRepository
from app.domain.models import Quote
from app.main import create_app


class FakeMarketSource:
    def quotes(self, tickers: list[str]) -> list[Quote]:
        return [
            Quote(ticker=ticker, price="110.00", day_change_pct="2.50", currency="USD")
            for ticker in tickers
        ]


def test_quote_refresh_reads_watchlist_and_updates_cache(db_path, tmp_path) -> None:
    watchlist = tmp_path / "watchlist.yaml"
    watchlist.write_text(
        """
watchlist:
  - ticker: NVDA
    name: NVIDIA Corporation
    market: US
    instrument: STOCK
    us_situs: true
    thesis_tag: ai-core
""".strip(),
        encoding="utf-8",
    )
    app = create_app(
        db_path=db_path,
        market_data_source=FakeMarketSource(),
        watchlist_path=watchlist,
    )

    response = TestClient(app).post("/api/quotes/refresh")

    assert response.status_code == 200
    assert response.json() == {"tickers": ["NVDA"], "quotes_refreshed": 1}
    repo = LedgerRepository(app.state.conn)
    assert repo.list_quotes()[0]["ticker"] == "NVDA"
    assert repo.list_instruments()[0]["thesis_tag"] == "ai-core"
