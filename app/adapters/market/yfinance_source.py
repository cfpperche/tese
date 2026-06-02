from app.domain.models import Quote
from app.domain.money import dec, money

try:
    import yfinance as yf
except ImportError:  # pragma: no cover - exercised only when optional dep is absent
    yf = None


class YFinanceSource:
    def quotes(self, tickers: list[str]) -> list[Quote]:
        if yf is None:
            raise RuntimeError("yfinance is not installed")
        quotes: list[Quote] = []
        for ticker in tickers:
            info = yf.Ticker(ticker).fast_info
            price = _get(info, "lastPrice")
            previous_close = _get(info, "previousClose")
            currency = _get(info, "currency") or "USD"
            change = dec("0")
            if previous_close:
                change = ((dec(price) - dec(previous_close)) / dec(previous_close)) * dec("100")
            quotes.append(
                Quote(
                    ticker=ticker.upper(),
                    price=money(price),
                    day_change_pct=money(change),
                    currency=str(currency),
                )
            )
        return quotes


def _get(info, key: str):
    if hasattr(info, key):
        return getattr(info, key)
    return info.get(key)
