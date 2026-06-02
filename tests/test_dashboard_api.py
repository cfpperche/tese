from fastapi.testclient import TestClient

from app.db.repositories import LedgerRepository
from app.main import create_app


def test_dashboard_api_returns_positions_and_quote_data(db_path) -> None:
    app = create_app(db_path=db_path)
    repo = LedgerRepository(app.state.conn)
    repo.add_trade(
        event_id="t1",
        date="2026-06-03",
        ticker="NVDA",
        market="US",
        currency="USD",
        instrument="STOCK",
        us_situs=True,
        side="BUY",
        origin="NORMAL",
        qty="2",
        unit_price="100.00",
        commission="0.00",
        fx_to_brl="5.00",
        fx_provenance="broker contract",
    )
    repo.upsert_quote("NVDA", price="110.00", day_change_pct="2.50", currency="USD")

    client = TestClient(app)
    response = client.get("/api/dashboard")

    assert response.status_code == 200
    payload = response.json()
    assert payload["positions"][0]["ticker"] == "NVDA"
    assert payload["positions"][0]["qty"] == "2"
    assert payload["positions"][0]["market_value_usd"] == "220.00"
    assert payload["positions"][0]["market_value_brl"] == "1100.00"
    assert payload["positions"][0]["unrealized_pl_brl"] == "100.00"
    assert payload["quotes"][0]["ticker"] == "NVDA"
    assert payload["quotes"][0]["day_change_pct"] == "2.50"
    assert payload["category"] == {"tickers": 1, "avg_day_change_pct": "2.50"}
