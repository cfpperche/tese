from __future__ import annotations

import sqlite3
from collections.abc import Iterator
from typing import Annotated

from fastapi import Depends, Request

from app.db.connection import connect


def get_conn(request: Request) -> Iterator[sqlite3.Connection]:
    """Yield a per-request SQLite connection.

    A single shared ``app.state.conn`` is not safe to use concurrently across
    Uvicorn's threadpool: sync handlers run in separate threads and concurrent
    ``execute()`` calls on one connection corrupt cursor state (observed as an
    intermittent ``IndexError: tuple index out of range`` when the dashboard and
    ledger-events endpoints are fetched in parallel). Opening a fresh connection
    per request — cheap for a local single-file DB — isolates each handler.

    ``app.state.conn`` remains for startup migration and as the seeding handle
    used by tests; it is no longer touched by request handlers.
    """
    conn = connect(request.app.state.db_path)
    try:
        yield conn
    finally:
        conn.close()


# Route-handler annotation: `conn: ConnDep` resolves a per-request connection.
ConnDep = Annotated[sqlite3.Connection, Depends(get_conn)]
