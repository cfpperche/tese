from pathlib import Path
from typing import Any

import yaml

from app.db.repositories import LedgerRepository


class ManualHoldingsSource:
    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)

    def ingest(self, repo: LedgerRepository) -> None:
        import_holdings_yaml(repo, self.path)


def import_holdings_yaml(repo: LedgerRepository, path: str | Path) -> None:
    data: dict[str, Any] = yaml.safe_load(Path(path).read_text(encoding="utf-8")) or {}
    for item in data.get("holdings", []):
        repo.add_trade(
            event_id=item["id"],
            date=item["date"],
            ticker=item["ticker"],
            market=item.get("market", "US"),
            currency=item.get("currency", "USD"),
            instrument=item.get("instrument", "STOCK"),
            us_situs=bool(item.get("us_situs", True)),
            side="BUY",
            origin="OPENING_IMPORT",
            qty=str(item["qty"]),
            unit_price=str(item["unit_price"]),
            commission=str(item.get("commission", "0.00")),
            fx_to_brl=str(item["fx_to_brl"]),
            fx_provenance=item["fx_provenance"],
            basis_provenance=item.get("basis_provenance", "UNVERIFIED"),
            linked_remittance_id=item.get("linked_remittance_id"),
            source="IMPORT",
        )
