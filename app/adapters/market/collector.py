from pathlib import Path
from typing import Any

import yaml

from app.adapters.market.base import MarketDataSource
from app.db.repositories import LedgerRepository


def load_watchlist(path: str | Path) -> list[dict[str, Any]]:
    watchlist_path = Path(path)
    if not watchlist_path.exists():
        fallback = Path("watchlist.example.yaml")
        if fallback.exists():
            watchlist_path = fallback
        else:
            return []
    data = yaml.safe_load(watchlist_path.read_text(encoding="utf-8")) or {}
    return list(data.get("watchlist", []))


def refresh_quotes(
    repo: LedgerRepository,
    source: MarketDataSource,
    watchlist_path: str | Path,
) -> dict[str, Any]:
    watchlist = load_watchlist(watchlist_path)
    for item in watchlist:
        repo.upsert_instrument(
            item["ticker"],
            name=item.get("name"),
            market=item.get("market", "US"),
            instrument=item.get("instrument", "STOCK"),
            us_situs=bool(item.get("us_situs", True)),
            thesis_tag=item.get("thesis_tag"),
        )
    tickers = [item["ticker"] for item in watchlist]
    quotes = source.quotes(tickers) if tickers else []
    for quote in quotes:
        repo.upsert_quote(
            quote.ticker,
            price=quote.price,
            day_change_pct=quote.day_change_pct,
            currency=quote.currency,
        )
    return {"tickers": tickers, "quotes_refreshed": len(quotes)}
