from fastapi.testclient import TestClient

from app.main import create_app


def test_ledger_api_records_and_corrects_event_without_editing(db_path) -> None:
    app = create_app(db_path=db_path)
    client = TestClient(app)

    create_response = client.post(
        "/api/ledger/events",
        json={
            "event_type": "remittance",
            "event_id": "r1",
            "date": "2026-06-02",
            "brl_amount": "33969.60",
            "usd_credited": "6000.00",
            "fx_rate": "5.60",
            "fx_provenance": "broker contract",
            "iof": "369.60",
            "wire_fee": "0.00",
            "source_account": "own CPF",
            "broker": "IBKR",
        },
    )
    correction_response = client.post(
        "/api/ledger/events/r1/correct",
        json={"correction_id": "c1", "date": "2026-06-03", "reason": "wrong FX"},
    )

    assert create_response.status_code == 200
    assert correction_response.status_code == 200
    events = {event["id"]: event for event in client.get("/api/ledger/events").json()}
    assert events["r1"]["voided_by"] == "c1"
    assert events["c1"]["event_type"] == "correction"
