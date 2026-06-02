from app.adapters.portfolio.manual_holdings import import_holdings_yaml


def test_holdings_yaml_import_creates_opening_import_without_fake_remittance(
    repo,
    tmp_path,
) -> None:
    path = tmp_path / "holdings.yaml"
    path.write_text(
        """
holdings:
  - id: opening-nvda
    date: "2026-01-02"
    ticker: NVDA
    market: US
    currency: USD
    instrument: STOCK
    us_situs: true
    qty: "3"
    unit_price: "100.00"
    commission: "1.00"
    fx_to_brl: "5.00"
    fx_provenance: contador supplied
    basis_provenance: CONTADOR_SUPPLIED
""".strip(),
        encoding="utf-8",
    )

    import_holdings_yaml(repo, path)

    events = repo.list_events()
    assert [event["event_type"] for event in events] == ["trade"]
    trade = events[0]
    assert trade["id"] == "opening-nvda"
    assert trade["origin"] == "OPENING_IMPORT"
    assert trade["basis_provenance"] == "CONTADOR_SUPPLIED"
    assert trade["linked_remittance_id"] is None
    assert not [event for event in events if event["event_type"] == "remittance"]
