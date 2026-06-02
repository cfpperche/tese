from collections.abc import Iterator
from pathlib import Path

import pytest

from app.db.connection import connect
from app.db.migrations import migrate
from app.db.repositories import LedgerRepository


@pytest.fixture()
def db_path(tmp_path: Path) -> Path:
    return tmp_path / "test.sqlite"


@pytest.fixture()
def conn(db_path: Path) -> Iterator:
    connection = connect(db_path)
    migrate(connection)
    try:
        yield connection
    finally:
        connection.close()


@pytest.fixture()
def repo(conn) -> LedgerRepository:
    return LedgerRepository(conn)


def seed_golden_ledger(repo: LedgerRepository) -> None:
    fixture_path = Path("docs/specs/001-foundation/fixtures/golden-ledger.md")
    assert fixture_path.exists(), "golden fixture must stay in the spec directory"

    repo.add_btc_origin(
        event_id="x1",
        date="2026-06-01",
        brl_proceeds="33600.00",
        acq_cost_brl="12000.00",
        gain_brl="21600.00",
        exempt_35k=True,
        in1888_reportable=True,
        source="MANUAL",
    )
    repo.add_remittance(
        event_id="r1",
        date="2026-06-02",
        brl_amount="33969.60",
        usd_credited="6000.00",
        fx_rate="5.60",
        fx_provenance="broker contract",
        iof="369.60",
        wire_fee="0.00",
        source_account="own CPF",
        broker="IBKR",
        source="MANUAL",
    )
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
        qty="10",
        unit_price="100.00",
        commission="1.00",
        fx_to_brl="5.60",
        fx_provenance="broker contract",
        source="MANUAL",
    )
    repo.add_trade(
        event_id="t2",
        date="2026-06-10",
        ticker="NVDA",
        market="US",
        currency="USD",
        instrument="STOCK",
        us_situs=True,
        side="BUY",
        origin="NORMAL",
        qty="50",
        unit_price="120.00",
        commission="1.00",
        fx_to_brl="5.70",
        fx_provenance="broker contract",
        source="MANUAL",
    )
    repo.correct_event(
        target_event_id="t2",
        correction_id="c1",
        date="2026-06-10",
        reason="qty typo 50->5",
        source="MANUAL",
    )
    repo.add_trade(
        event_id="t3",
        date="2026-06-10",
        ticker="NVDA",
        market="US",
        currency="USD",
        instrument="STOCK",
        us_situs=True,
        side="BUY",
        origin="NORMAL",
        qty="5",
        unit_price="120.00",
        commission="1.00",
        fx_to_brl="5.70",
        fx_provenance="broker contract",
        source="MANUAL",
    )
    repo.add_trade(
        event_id="t4",
        date="2026-07-01",
        ticker="NVDA",
        market="US",
        currency="USD",
        instrument="STOCK",
        us_situs=True,
        side="SELL",
        origin="NORMAL",
        qty="6",
        unit_price="130.00",
        commission="1.00",
        fx_to_brl="5.80",
        fx_provenance="broker contract",
        source="MANUAL",
    )
    repo.add_dividend(
        event_id="d1",
        date="2026-09-15",
        ticker="NVDA",
        gross="4.00",
        currency="USD",
        foreign_tax_withheld="1.20",
        net="2.80",
        fx_to_brl="5.75",
        fx_provenance="broker contract",
        source="MANUAL",
    )
    repo.add_year_end_balance(
        event_id="y1",
        date="2026-12-31",
        tax_year=2026,
        ticker="NVDA",
        qty="9",
        price="140.00",
        price_provenance="yfinance close",
        fx_rate="5.50",
        fx_provenance="PTAX 31/12",
        source="MANUAL",
    )
