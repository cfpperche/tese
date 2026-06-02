# 001 - foundation - tasks

_Generated from `plan.md` on 2026-06-02. Work top-to-bottom. Check boxes as tasks complete. If a task reveals the plan is wrong, update `plan.md` before continuing._

## Implementation

- [x] 1. Scaffold the Python app/tooling: `pyproject.toml`, package directories, pytest/ruff config, sample env/config files, and local-data gitignore rules.
- [x] 2. Write the red-first golden export test from `fixtures/golden-ledger.md`, asserting both `events.csv` audit completeness and `summary.json` derived values.
- [x] 3. Write the required `OPENING_IMPORT`/`basis_provenance` test for `holdings.yaml` import, with no fake remittance-derived basis.
- [x] 4. Write the append-only correction/void test proving correction inserts a new row and export/projections derive `voided_by` without UPDATE/DELETE on original events.
- [x] 5. Write dashboard/API and mocked yfinance adapter tests for the Phase 1 integration surface.
- [x] 6. Implement SQLite connection, migrations, and repository methods for ledger, instruments, quote cache, and migrations metadata.
- [x] 7. Implement domain models, Decimal money helpers, event validation, correction/void orchestration, and weighted-average derivations.
- [x] 8. Implement contador-ready export generation: complete `events.csv` audit trail and tax-year `summary.json`.
- [x] 9. Implement manual holdings import as `OPENING_IMPORT` trade events with explicit `basis_provenance`.
- [x] 10. Implement market-data adapter interface plus `YFinanceSource`, keeping yfinance isolated from domain/API code.
- [x] 11. Implement FastAPI app, health route, ledger routes, dashboard projection route, export route, and static file serving.
- [x] 12. Implement the static vanilla JS frontend for dashboard, ledger entry, correction/void flow, and export action/status.
- [x] 13. Update README run/test/export instructions and clarify system-design correction projection if implementation confirms the plan detail.
- [x] 14. Update this checklist and `notes.md` for any non-trivial deviations discovered during implementation.

## Verification

- [x] Run the full test suite and verify golden export, opening import, append-only correction, dashboard API, and yfinance adapter tests pass.
- [x] Run lint/format checks declared by `pyproject.toml`.
- [x] Smoke-test local app startup with Uvicorn and verify the static dashboard and `/health` respond.
- [x] Verify spec-001 done-when items: local dashboard works, full ledger event set can be recorded/corrected, one-command export reproduces the fixture, and adapter boundaries remain in place.
- [x] Update `.agent0/HANDOFF.md` with final state and next actions.

## Notes

- Implementation started from the ledger/export contract. The dashboard is required for Phase 1, but the golden fixture remains the correctness oracle.
