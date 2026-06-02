from __future__ import annotations

import sqlite3
from collections.abc import Mapping
from datetime import UTC, datetime
from typing import Any

from app.domain.money import dec, money

DETAIL_TABLES = {
    "remittance": "remittance",
    "trade": "trade",
    "dividend": "dividend",
    "btc_origin": "btc_origin",
    "year_end_balance": "year_end_balance",
    "correction": "correction",
}


class LedgerRepository:
    def __init__(self, conn: sqlite3.Connection) -> None:
        self.conn = conn

    def _insert_event(
        self,
        event_type: str,
        event_id: str,
        date: str,
        source: str = "MANUAL",
        notes: str | None = None,
    ) -> None:
        self.conn.execute(
            """
            INSERT INTO ledger_events (id, event_type, date, created_at, source, notes)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                event_id,
                event_type,
                date,
                datetime.now(UTC).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
                source,
                notes,
            ),
        )

    def _event_type_for(self, event_id: str) -> str:
        row = self.conn.execute(
            "SELECT event_type FROM ledger_events WHERE id = ?", (event_id,)
        ).fetchone()
        if row is None:
            raise ValueError(f"unknown event id: {event_id}")
        return str(row["event_type"])

    def add_btc_origin(
        self,
        *,
        event_id: str,
        date: str,
        brl_proceeds: str,
        acq_cost_brl: str,
        gain_brl: str,
        exempt_35k: bool,
        in1888_reportable: bool,
        source: str = "MANUAL",
        notes: str | None = None,
    ) -> None:
        with self.conn:
            self._insert_event("btc_origin", event_id, date, source, notes)
            self.conn.execute(
                """
                INSERT INTO btc_origin (
                  event_id, brl_proceeds, acq_cost_brl, gain_brl, exempt_35k, in1888_reportable
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    event_id,
                    money(brl_proceeds),
                    money(acq_cost_brl),
                    money(gain_brl),
                    int(exempt_35k),
                    int(in1888_reportable),
                ),
            )

    def add_remittance(
        self,
        *,
        event_id: str,
        date: str,
        brl_amount: str,
        usd_credited: str,
        fx_rate: str,
        fx_provenance: str,
        iof: str = "0.00",
        wire_fee: str = "0.00",
        source_account: str | None = None,
        broker: str | None = None,
        source: str = "MANUAL",
        notes: str | None = None,
    ) -> None:
        with self.conn:
            self._insert_event("remittance", event_id, date, source, notes)
            self.conn.execute(
                """
                INSERT INTO remittance (
                  event_id, brl_amount, usd_credited, fx_rate, fx_provenance, iof, wire_fee,
                  source_account, broker
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    event_id,
                    money(brl_amount),
                    money(usd_credited),
                    str(fx_rate),
                    fx_provenance,
                    money(iof),
                    money(wire_fee),
                    source_account,
                    broker,
                ),
            )

    def add_trade(
        self,
        *,
        event_id: str,
        date: str,
        ticker: str,
        market: str,
        currency: str,
        instrument: str,
        us_situs: bool,
        side: str,
        origin: str,
        qty: str,
        unit_price: str,
        commission: str,
        fx_to_brl: str,
        fx_provenance: str,
        brl_value: str | None = None,
        basis_provenance: str | None = None,
        linked_remittance_id: str | None = None,
        source: str = "MANUAL",
        notes: str | None = None,
    ) -> None:
        side = side.upper()
        origin = origin.upper()
        if brl_value is None:
            gross = dec(qty) * dec(unit_price)
            signed = gross + dec(commission) if side == "BUY" else gross - dec(commission)
            brl_value = money(signed * dec(fx_to_brl))
        with self.conn:
            self._insert_event("trade", event_id, date, source, notes)
            self.conn.execute(
                """
                INSERT INTO trade (
                  event_id, ticker, market, currency, instrument, us_situs, side, origin, qty,
                  unit_price, commission, fx_to_brl, fx_provenance, brl_value,
                  basis_provenance, linked_remittance_id
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    event_id,
                    ticker.upper(),
                    market,
                    currency,
                    instrument,
                    int(us_situs),
                    side,
                    origin,
                    str(qty),
                    money(unit_price),
                    money(commission),
                    str(fx_to_brl),
                    fx_provenance,
                    money(brl_value),
                    basis_provenance,
                    linked_remittance_id,
                ),
            )
            self.conn.execute(
                """
                INSERT INTO instrument_ref (ticker, name, market, instrument, us_situs)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(ticker) DO UPDATE SET
                  market = excluded.market,
                  instrument = excluded.instrument,
                  us_situs = excluded.us_situs
                """,
                (ticker.upper(), ticker.upper(), market, instrument, int(us_situs)),
            )

    def add_dividend(
        self,
        *,
        event_id: str,
        date: str,
        ticker: str,
        gross: str,
        currency: str,
        foreign_tax_withheld: str,
        net: str,
        fx_to_brl: str,
        fx_provenance: str,
        source: str = "MANUAL",
        notes: str | None = None,
    ) -> None:
        with self.conn:
            self._insert_event("dividend", event_id, date, source, notes)
            self.conn.execute(
                """
                INSERT INTO dividend (
                  event_id, ticker, gross, currency, foreign_tax_withheld, net,
                  fx_to_brl, fx_provenance
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    event_id,
                    ticker.upper(),
                    money(gross),
                    currency,
                    money(foreign_tax_withheld),
                    money(net),
                    str(fx_to_brl),
                    fx_provenance,
                ),
            )

    def add_year_end_balance(
        self,
        *,
        event_id: str,
        date: str,
        tax_year: int,
        ticker: str,
        qty: str,
        price: str,
        price_provenance: str,
        fx_rate: str,
        fx_provenance: str,
        brl_value: str | None = None,
        usd_value: str | None = None,
        source: str = "MANUAL",
        notes: str | None = None,
    ) -> None:
        usd_value = money(dec(usd_value) if usd_value is not None else dec(qty) * dec(price))
        brl_value = money(
            dec(brl_value) if brl_value is not None else dec(usd_value) * dec(fx_rate)
        )
        with self.conn:
            self._insert_event("year_end_balance", event_id, date, source, notes)
            self.conn.execute(
                """
                INSERT INTO year_end_balance (
                  event_id, tax_year, ticker, qty, price, price_provenance, fx_rate,
                  fx_provenance, brl_value, usd_value
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    event_id,
                    tax_year,
                    ticker.upper(),
                    str(qty),
                    money(price),
                    price_provenance,
                    str(fx_rate),
                    fx_provenance,
                    brl_value,
                    usd_value,
                ),
            )

    def correct_event(
        self,
        target_event_id: str,
        *,
        correction_id: str,
        date: str,
        reason: str,
        source: str = "MANUAL",
        notes: str | None = None,
    ) -> None:
        target_table = DETAIL_TABLES[self._event_type_for(target_event_id)]
        with self.conn:
            self._insert_event("correction", correction_id, date, source, notes)
            self.conn.execute(
                """
                INSERT INTO correction (event_id, target_table, target_event_id, reason)
                VALUES (?, ?, ?, ?)
                """,
                (correction_id, target_table, target_event_id, reason),
            )

    def upsert_quote(
        self, ticker: str, *, price: str, day_change_pct: str, currency: str = "USD"
    ) -> None:
        with self.conn:
            self.conn.execute(
                """
                INSERT INTO quote_cache (ticker, price, day_change_pct, currency)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(ticker) DO UPDATE SET
                  ts = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
                  price = excluded.price,
                  day_change_pct = excluded.day_change_pct,
                  currency = excluded.currency
                """,
                (ticker.upper(), money(price), money(day_change_pct), currency),
            )

    def upsert_instrument(
        self,
        ticker: str,
        *,
        name: str | None = None,
        market: str = "US",
        instrument: str = "STOCK",
        us_situs: bool = True,
        thesis_tag: str | None = None,
    ) -> None:
        with self.conn:
            self.conn.execute(
                """
                INSERT INTO instrument_ref (ticker, name, market, instrument, us_situs, thesis_tag)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(ticker) DO UPDATE SET
                  name = excluded.name,
                  market = excluded.market,
                  instrument = excluded.instrument,
                  us_situs = excluded.us_situs,
                  thesis_tag = excluded.thesis_tag
                """,
                (
                    ticker.upper(),
                    name or ticker.upper(),
                    market,
                    instrument,
                    int(us_situs),
                    thesis_tag,
                ),
            )

    def list_instruments(self) -> list[dict[str, Any]]:
        rows = self.conn.execute("SELECT * FROM instrument_ref ORDER BY ticker").fetchall()
        instruments = []
        for row in rows:
            item = dict(row)
            item["us_situs"] = bool(item["us_situs"])
            instruments.append(item)
        return instruments

    def list_quotes(self) -> list[dict[str, Any]]:
        return [dict(row) for row in self.conn.execute("SELECT * FROM quote_cache ORDER BY ticker")]

    def list_events(self) -> list[dict[str, Any]]:
        voided_by = {
            row["target_event_id"]: row["event_id"]
            for row in self.conn.execute("SELECT event_id, target_event_id FROM correction")
        }
        rows = self.conn.execute(
            "SELECT * FROM ledger_events ORDER BY date, seq"
        ).fetchall()
        events: list[dict[str, Any]] = []
        for row in rows:
            event = dict(row)
            event["voided_by"] = voided_by.get(event["id"])
            table = DETAIL_TABLES[event["event_type"]]
            detail = self.conn.execute(
                f"SELECT * FROM {table} WHERE event_id = ?", (event["id"],)
            ).fetchone()
            if detail:
                event.update(_normalize_detail(dict(detail)))
            events.append(event)
        return events


def _normalize_detail(detail: Mapping[str, Any]) -> dict[str, Any]:
    normalized = dict(detail)
    normalized.pop("event_id", None)
    for key in ("us_situs", "exempt_35k", "in1888_reportable"):
        if key in normalized and normalized[key] is not None:
            normalized[key] = bool(normalized[key])
    return normalized
