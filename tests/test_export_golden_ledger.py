import csv
from io import StringIO

from app.domain.export import generate_tax_year_export

from .conftest import seed_golden_ledger


def test_golden_ledger_export_matches_fixture(repo) -> None:
    seed_golden_ledger(repo)

    package = generate_tax_year_export(repo.conn, 2026)
    rows = list(csv.DictReader(StringIO(package.events_csv)))
    by_id = {row["id"]: row for row in rows}

    assert set(by_id) == {"x1", "r1", "t1", "t2", "c1", "t3", "t4", "d1", "y1"}
    assert by_id["t2"]["voided_by"] == "c1"
    assert by_id["c1"]["event_type"] == "correction"

    summary = package.summary
    position = summary["positions"][0]
    assert position["ticker"] == "NVDA"
    assert position["qty"] == "9"
    assert position["avg_cost_brl"] == "602.09"
    assert position["cost_basis_brl"] == "5418.78"
    assert position["market_value_brl"] == "6930.00"
    assert position["unrealized_pl_brl"] == "1511.22"

    assert summary["realized_gains_brl"] == "905.68"
    assert summary["dividends"] == {
        "gross_brl": "23.00",
        "foreign_tax_withheld_brl": "6.90",
        "net_brl": "16.10",
    }
    assert summary["remittances"] == [
        {
            "id": "r1",
            "date": "2026-06-02",
            "brl_amount": "33969.60",
            "usd_credited": "6000.00",
            "iof": "369.60",
            "fx_rate": "5.60",
            "fx_provenance": "broker contract",
        }
    ]
    assert summary["btc_origin"] == {
        "id": "x1",
        "date": "2026-06-01",
        "gain_brl": "21600.00",
        "exempt_35k": True,
        "in1888_reportable": True,
    }
    assert summary["flags"] == {
        "us_situs_usd_total": "1260.00",
        "estate_tax_flag": False,
        "foreign_assets_usd_total": "1260.00",
        "cbe_flag": False,
    }
    assert summary["realized_gain_source"] == "DERIVED"
