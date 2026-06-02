from __future__ import annotations

import sqlite3
from collections import defaultdict
from typing import Any

from app.db.repositories import LedgerRepository
from app.domain.money import dec, money, qty_text


def tax_year_summary(conn: sqlite3.Connection, tax_year: int) -> dict[str, Any]:
    repo = LedgerRepository(conn)
    events = repo.list_events()
    active = [event for event in events if not event["voided_by"]]
    positions, realized_gain = _derive_positions_and_realized(active, tax_year)
    yeb_rows = [
        event
        for event in active
        if event["event_type"] == "year_end_balance" and int(event["tax_year"]) == tax_year
    ]

    summary_positions = []
    for event in yeb_rows:
        ticker = event["ticker"]
        basis = positions.get(ticker, {}).get("cost_basis_brl", dec("0"))
        qty = dec(event["qty"])
        avg = basis / qty if qty else dec("0")
        market = dec(event["brl_value"])
        instrument = _instrument(conn, ticker)
        summary_positions.append(
            {
                "ticker": ticker,
                "qty": qty_text(qty),
                "avg_cost_brl": money(avg),
                "cost_basis_brl": money(basis),
                "market_value_brl": money(market),
                "unrealized_pl_brl": money(market - basis),
                "usd_value": money(event["usd_value"]),
                "us_situs": bool(instrument.get("us_situs", True)),
                "price_provenance": event["price_provenance"],
                "fx_provenance": event["fx_provenance"],
            }
        )

    dividends = _dividends(active, tax_year)
    remittances = _remittances(active, tax_year)
    btc_origin = _btc_origin(active, tax_year)
    flags = _flags(summary_positions)
    return {
        "generated_for_tax_year": tax_year,
        "positions": summary_positions,
        "realized_gains_brl": money(realized_gain),
        "realized_gain_source": "DERIVED",
        "dividends": dividends,
        "remittances": remittances,
        "btc_origin": btc_origin,
        "flags": flags,
    }


def dashboard_projection(conn: sqlite3.Connection) -> dict[str, Any]:
    repo = LedgerRepository(conn)
    active = [event for event in repo.list_events() if not event["voided_by"]]
    positions, _realized_gain = _derive_positions_and_realized(active, None)
    quotes = {quote["ticker"]: quote for quote in repo.list_quotes()}
    total_value = dec("0")
    rendered_positions: list[dict[str, Any]] = []
    for ticker, position in sorted(positions.items()):
        quote = quotes.get(ticker)
        market_value_usd = dec("0")
        market_value_brl = dec("0")
        if quote:
            market_value_usd = position["qty"] * dec(quote["price"])
            market_value_brl = market_value_usd * position["latest_fx_to_brl"]
        total_value += market_value_usd
        rendered_positions.append(
            {
                "ticker": ticker,
                "qty": qty_text(position["qty"]),
                "avg_cost_brl": money(position["avg_cost_brl"]),
                "cost_basis_brl": money(position["cost_basis_brl"]),
                "market_value_usd": money(market_value_usd),
                "market_value_brl": money(market_value_brl),
                "unrealized_pl_brl": money(market_value_brl - position["cost_basis_brl"]),
                "day_change_pct": quote["day_change_pct"] if quote else None,
            }
        )
    for position in rendered_positions:
        value = dec(position["market_value_usd"])
        position["portfolio_weight_pct"] = (
            money((value / total_value) * 100) if total_value else "0.00"
        )

    day_changes = [dec(quote["day_change_pct"]) for quote in quotes.values()]
    return {
        "category": {
            "tickers": len(quotes),
            "avg_day_change_pct": (
                money(sum(day_changes, dec("0")) / len(day_changes)) if day_changes else "0.00"
            ),
        },
        "positions": rendered_positions,
        "quotes": [
            {
                "ticker": quote["ticker"],
                "price": quote["price"],
                "day_change_pct": quote["day_change_pct"],
                "currency": quote["currency"],
                "ts": quote["ts"],
            }
            for quote in sorted(quotes.values(), key=lambda item: item["ticker"])
        ],
    }


def _derive_positions_and_realized(
    events: list[dict[str, Any]], tax_year: int | None
) -> tuple[dict[str, dict[str, Any]], Any]:
    positions: dict[str, dict[str, Any]] = defaultdict(
        lambda: {
            "qty": dec("0"),
            "cost_basis_brl": dec("0"),
            "avg_cost_brl": dec("0"),
            "latest_fx_to_brl": dec("0"),
        }
    )
    realized_gain = dec("0")
    for event in events:
        if event["event_type"] != "trade":
            continue
        ticker = event["ticker"]
        qty = dec(event["qty"])
        position = positions[ticker]
        position["latest_fx_to_brl"] = dec(event["fx_to_brl"])
        if event["side"] == "BUY":
            position["qty"] += qty
            position["cost_basis_brl"] += dec(event["brl_value"])
            position["avg_cost_brl"] = (
                position["cost_basis_brl"] / position["qty"] if position["qty"] else dec("0")
            )
            continue

        avg_cost = position["cost_basis_brl"] / position["qty"] if position["qty"] else dec("0")
        cost_of_sold = avg_cost * qty
        net_proceeds = dec(event["brl_value"])
        if tax_year is None or event["date"].startswith(f"{tax_year}-"):
            realized_gain += net_proceeds - cost_of_sold
        position["qty"] -= qty
        position["cost_basis_brl"] -= cost_of_sold
        position["avg_cost_brl"] = (
            position["cost_basis_brl"] / position["qty"] if position["qty"] else dec("0")
        )
    return dict(positions), realized_gain


def _dividends(events: list[dict[str, Any]], tax_year: int) -> dict[str, str]:
    gross = withheld = net = dec("0")
    for event in events:
        if event["event_type"] != "dividend" or not event["date"].startswith(f"{tax_year}-"):
            continue
        fx = dec(event["fx_to_brl"])
        gross += dec(event["gross"]) * fx
        withheld += dec(event["foreign_tax_withheld"]) * fx
        net += dec(event["net"]) * fx
    return {
        "gross_brl": money(gross),
        "foreign_tax_withheld_brl": money(withheld),
        "net_brl": money(net),
    }


def _remittances(events: list[dict[str, Any]], tax_year: int) -> list[dict[str, str]]:
    return [
        {
            "id": event["id"],
            "date": event["date"],
            "brl_amount": event["brl_amount"],
            "usd_credited": event["usd_credited"],
            "iof": event["iof"],
            "fx_rate": event["fx_rate"],
            "fx_provenance": event["fx_provenance"],
        }
        for event in events
        if event["event_type"] == "remittance" and event["date"].startswith(f"{tax_year}-")
    ]


def _btc_origin(events: list[dict[str, Any]], tax_year: int) -> dict[str, Any] | None:
    for event in events:
        if event["event_type"] == "btc_origin" and event["date"].startswith(f"{tax_year}-"):
            return {
                "id": event["id"],
                "date": event["date"],
                "gain_brl": event["gain_brl"],
                "exempt_35k": event["exempt_35k"],
                "in1888_reportable": event["in1888_reportable"],
            }
    return None


def _flags(positions: list[dict[str, Any]]) -> dict[str, Any]:
    foreign_assets = sum((dec(position["usd_value"]) for position in positions), dec("0"))
    us_situs = sum(
        (dec(position["usd_value"]) for position in positions if position["us_situs"]), dec("0")
    )
    return {
        "us_situs_usd_total": money(us_situs),
        "estate_tax_flag": us_situs >= dec("60000"),
        "foreign_assets_usd_total": money(foreign_assets),
        "cbe_flag": foreign_assets >= dec("1000000"),
    }


def _instrument(conn: sqlite3.Connection, ticker: str) -> dict[str, Any]:
    row = conn.execute("SELECT * FROM instrument_ref WHERE ticker = ?", (ticker,)).fetchone()
    if row is None:
        return {"us_situs": True}
    result = dict(row)
    result["us_situs"] = bool(result["us_situs"])
    return result
