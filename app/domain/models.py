from dataclasses import dataclass


@dataclass(frozen=True)
class Quote:
    ticker: str
    price: str
    day_change_pct: str
    currency: str
