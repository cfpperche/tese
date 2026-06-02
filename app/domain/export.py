from __future__ import annotations

import csv
import json
import sqlite3
from dataclasses import dataclass
from io import StringIO
from pathlib import Path
from typing import Any

from app.db.repositories import LedgerRepository
from app.domain.derivations import tax_year_summary

EVENT_COLUMNS = [
    "id",
    "event_type",
    "date",
    "source",
    "voided_by",
    "ticker",
    "market",
    "currency",
    "instrument",
    "us_situs",
    "side",
    "origin",
    "qty",
    "unit_price",
    "commission",
    "fx_to_brl",
    "fx_rate",
    "fx_provenance",
    "brl_value",
    "brl_amount",
    "usd_credited",
    "iof",
    "wire_fee",
    "source_account",
    "broker",
    "basis_provenance",
    "linked_remittance_id",
    "gross",
    "foreign_tax_withheld",
    "net",
    "brl_proceeds",
    "acq_cost_brl",
    "gain_brl",
    "exempt_35k",
    "in1888_reportable",
    "tax_year",
    "price",
    "price_provenance",
    "usd_value",
    "target_table",
    "target_event_id",
    "reason",
    "notes",
]


@dataclass(frozen=True)
class ExportPackage:
    events_csv: str
    summary: dict[str, Any]


def generate_tax_year_export(conn: sqlite3.Connection, tax_year: int) -> ExportPackage:
    repo = LedgerRepository(conn)
    return ExportPackage(
        events_csv=_events_csv(repo.list_events()),
        summary=tax_year_summary(conn, tax_year),
    )


def write_tax_year_export(conn: sqlite3.Connection, tax_year: int, out_dir: str | Path) -> Path:
    package = generate_tax_year_export(conn, tax_year)
    target = Path(out_dir) / str(tax_year)
    target.mkdir(parents=True, exist_ok=True)
    (target / "events.csv").write_text(package.events_csv, encoding="utf-8")
    (target / "summary.json").write_text(
        json.dumps(package.summary, indent=2, sort_keys=True), encoding="utf-8"
    )
    return target


def _events_csv(events: list[dict[str, Any]]) -> str:
    output = StringIO()
    writer = csv.DictWriter(output, fieldnames=EVENT_COLUMNS, extrasaction="ignore")
    writer.writeheader()
    for event in events:
        writer.writerow({column: _csv_value(event.get(column)) for column in EVENT_COLUMNS})
    return output.getvalue()


def _csv_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)
