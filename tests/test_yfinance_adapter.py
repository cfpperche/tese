from app.adapters.market.yfinance_source import YFinanceSource


class FakeFastInfo(dict):
    def __getattr__(self, key):
        return self[key]


class FakeTicker:
    def __init__(self, ticker: str) -> None:
        self.ticker = ticker
        self.fast_info = FakeFastInfo(
            lastPrice=110.0,
            previousClose=100.0,
            currency="USD",
        )


class FakeYF:
    Ticker = FakeTicker


def test_yfinance_source_normalizes_quote(monkeypatch) -> None:
    import app.adapters.market.yfinance_source as module

    monkeypatch.setattr(module, "yf", FakeYF)

    quote = YFinanceSource().quotes(["NVDA"])[0]

    assert quote.ticker == "NVDA"
    assert quote.price == "110.00"
    assert quote.day_change_pct == "10.00"
    assert quote.currency == "USD"
