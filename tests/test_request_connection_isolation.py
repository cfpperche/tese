"""Each request must get its own SQLite connection.

A single shared ``app.state.conn`` used across Uvicorn's threadpool races:
concurrent ``execute()`` calls on one connection corrupt cursor state. These
tests pin the fix — request handlers resolve a fresh per-request connection via
``app.api.deps.get_conn`` — so a regression back to the shared connection fails.
"""

from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

from app.api.deps import get_conn
from app.main import create_app


def test_get_conn_yields_a_fresh_connection_each_call(db_path: Path) -> None:
    app = create_app(db_path=db_path)
    request = SimpleNamespace(app=app)

    gen_a = get_conn(request)
    gen_b = get_conn(request)
    conn_a = next(gen_a)
    conn_b = next(gen_b)

    # Distinct from each other and from the shared startup/seed connection.
    assert conn_a is not conn_b
    assert conn_a is not app.state.conn
    assert conn_b is not app.state.conn

    # The dependency closes the connection on teardown.
    for gen in (gen_a, gen_b):
        try:
            next(gen)
        except StopIteration:
            pass


def test_parallel_reads_do_not_corrupt(db_path: Path) -> None:
    from concurrent.futures import ThreadPoolExecutor

    from app.db.repositories import LedgerRepository

    app = create_app(db_path=db_path)
    LedgerRepository(app.state.conn).add_trade(
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
        commission="0.00",
        fx_to_brl="5.60",
        fx_provenance="broker contract",
    )

    def read(_: int) -> bool:
        request = SimpleNamespace(app=app)
        gen = get_conn(request)
        conn = next(gen)
        try:
            # The exact pair the frontend fires in parallel via Promise.all.
            LedgerRepository(conn).list_events()
            from app.domain.derivations import dashboard_projection

            dashboard_projection(conn)
            return True
        finally:
            try:
                next(gen)
            except StopIteration:
                pass

    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(read, range(64)))

    assert all(results)
