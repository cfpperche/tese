def test_correction_appends_and_projects_voided_by_without_mutating_original(repo) -> None:
    repo.add_trade(
        event_id="bad-buy",
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
    )

    before = repo.conn.execute("select count(*) from ledger_events").fetchone()[0]
    repo.correct_event("bad-buy", correction_id="fix-buy", date="2026-06-10", reason="qty typo")
    after = repo.conn.execute("select count(*) from ledger_events").fetchone()[0]

    assert after == before + 1
    stored_trade = repo.conn.execute(
        "select event_type from ledger_events where id = ?", ("bad-buy",)
    ).fetchone()
    assert stored_trade["event_type"] == "trade"

    by_id = {event["id"]: event for event in repo.list_events()}
    assert by_id["bad-buy"]["voided_by"] == "fix-buy"
    assert by_id["fix-buy"]["event_type"] == "correction"
