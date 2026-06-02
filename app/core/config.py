import os
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    db_path: Path
    market_source: str = "yfinance"
    watchlist_path: Path = Path("watchlist.yaml")


def get_settings() -> Settings:
    return Settings(
        db_path=Path(os.getenv("TESE_DB_PATH", "data/tese.sqlite")),
        market_source=os.getenv("TESE_MARKET_SOURCE", "yfinance"),
        watchlist_path=Path(os.getenv("TESE_WATCHLIST_PATH", "watchlist.yaml")),
    )
