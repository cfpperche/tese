# 001 - foundation - plan

_Drafted from `spec.md` on 2026-06-02. Update this file if implementation reveals the plan is wrong; do NOT silently diverge._

## Approach

Build Phase 1 ledger-first, not dashboard-first. The first production-facing behavior must be a
failing export test seeded from `fixtures/golden-ledger.md`; only after that red test exists should
the implementation add schema, derivations, export code, API routes, and the static dashboard. The
golden fixture is the test oracle: `events.csv` must include the voided trade and correction event,
while `summary.json` must derive positions, realized gain, dividends, remittance, BTC origin, and
year-end flags from non-voided economic events.

Use a small local FastAPI app served by Uvicorn, with SQLite as the only datastore and explicit SQL
migrations/repositories rather than an ORM for the first cut. The ledger is append-only in behavior:
event creation inserts rows; correction/void appends a correction event; repository/export reads
derive the visible `voided_by` relation from correction rows instead of requiring UPDATE/DELETE on
the original economic event. Monetary math uses `Decimal` internally and rounds only at export
boundaries.

Keep the two data planes behind adapters from day one. `YFinanceSource` is the Phase 1 source-A
market-data adapter for watchlist quotes/day change because it needs no key and unblocks a personal
prototype. It must not leak into domain code; if yfinance breaks or a keyed provider is chosen later,
the adapter can be swapped. `ManualHoldings` is only a bootstrap/import path that creates
`OPENING_IMPORT` trade events with `basis_provenance`; positions after import are always derived
from trade events.

Use a static vanilla JavaScript frontend served by FastAPI. No Node build step. The MVP UI should
prioritize dense operational screens: dashboard summary, quote/position tables, ledger-entry forms,
correction/void flow, and export action/status. Charting can use a locally served UMD build if it
stays practical; otherwise the first dashboard may use lightweight tables/CSS bars and leave richer
charts for the next pass. Do not add CDN dependencies because the app is local-first and should not
make browser-side external calls beyond the chosen market-data plane.

## Files to touch

**Create:**
- `pyproject.toml` - project metadata, Python 3.12+, runtime deps, dev deps, pytest/ruff config.
- `.env.example` - documented local settings with no secrets.
- `watchlist.example.yaml` - tracked sample thesis universe for local copying.
- `holdings.example.yaml` - tracked sample bootstrap holdings import with no personal data.
- `app/__init__.py` - package marker.
- `app/main.py` - FastAPI app factory, JSON routes registration, static file mount, health route.
- `app/cli.py` - one-command export entrypoint, e.g. `python -m app.cli export --tax-year 2026`.
- `app/core/config.py` - settings, project paths, database path, source-A selection.
- `app/core/logging.py` - simple structured logging setup for collector/export runs.
- `app/db/connection.py` - SQLite connection factory and transaction helpers.
- `app/db/migrations/001_init.sql` - initial ledger, instrument, quote-cache, and metadata schema.
- `app/db/migrations.py` - idempotent migration runner for local startup/tests.
- `app/db/repositories.py` - append-only insert/read methods for ledger tables and projections.
- `app/domain/models.py` - Pydantic/dataclass domain models for events, quotes, positions, exports.
- `app/domain/money.py` - Decimal helpers and export rounding rules.
- `app/domain/ledger.py` - event validation and correction/void orchestration.
- `app/domain/derivations.py` - weighted-average cost, realized gain, dividends, position and flag roll-ups.
- `app/domain/export.py` - `events.csv` and `summary.json` generation for a tax year.
- `app/adapters/market/base.py` - `MarketDataSource` interface.
- `app/adapters/market/yfinance_source.py` - Phase 1 quote/day-change implementation.
- `app/adapters/portfolio/manual_holdings.py` - `holdings.yaml` to `OPENING_IMPORT` trade ingestion.
- `app/api/routes/dashboard.py` - dashboard JSON projection.
- `app/api/routes/ledger.py` - create/list/correct ledger events.
- `app/api/routes/export.py` - export trigger/status/download route for local UI use.
- `app/static/index.html` - first usable app screen, not a landing page.
- `app/static/app.js` - fetches API projections, renders dashboard/ledger/export UI.
- `app/static/styles.css` - design-system-aligned operational styling.
- `tests/conftest.py` - temp SQLite DB, migration fixture, test helpers.
- `tests/test_export_golden_ledger.py` - red-first golden fixture export assertions.
- `tests/test_opening_import.py` - required D8/D11 test for `holdings.yaml` -> `OPENING_IMPORT`.
- `tests/test_append_only_correction.py` - correction/void behavior without UPDATE/DELETE.
- `tests/test_dashboard_api.py` - API smoke test for derived dashboard data.
- `tests/test_yfinance_adapter.py` - adapter normalization with mocked yfinance responses.

**Modify:**
- `.gitignore` - also ignore local `watchlist.yaml`, export outputs, and the local SQLite data dir if introduced.
- `README.md` - replace TBD run section with install/run/test/export commands once implementation lands.
- `docs/system-design.md` - if implementation confirms the correction projection detail, clarify that exported `voided_by` is derived from correction rows and not a mutable original-row update.
- `docs/specs/001-foundation/notes.md` - create/use only during implementation if non-trivial deviations or decisions appear.

**Delete:**
- None.

## Alternatives considered

### Dashboard-first implementation

Rejected because it would optimize for the visually satisfying part while leaving the Phase 1 north
star unproven. The spec explicitly says the contador-ready export and golden fixture drive the
schema and tests; a dashboard alone is not done.

### `holdings.yaml` as a parallel source of truth

Rejected because Spec-001 debate decision D8 locked trades as the single portfolio truth.
`holdings.yaml` remains useful only as an import/bootstrap input that creates `OPENING_IMPORT`
trade events with basis provenance.

### ORM-first persistence

Rejected for the first cut. SQLAlchemy/SQLModel may be useful later, but explicit SQLite schema and
repository code make the append-only ledger, correction projection, and export math easier to audit
against the fixture. If query complexity grows, an ORM can be introduced after the contract tests
are green.

### Finnhub or Twelve Data as the first source-A provider

Rejected for the first runnable MVP because both add API-key/account friction before the ledger is
validated. The selected shape is `YFinanceSource` first, with the provider isolated behind
`MarketDataSource` so Finnhub can replace it later without changing domain or UI code.

### React/Vite or Python-native UI

Rejected for Phase 1. A React build adds project surface area before the data contract exists, and
Python-native quick UIs tend to blur API/domain boundaries. A static vanilla JS app served by
FastAPI is enough for a single-user local tool and keeps the first-run path simple.

### CDN-hosted Chart.js

Rejected because the project is local-first and the system design limits external calls to the
chosen market-data plane. If Chart.js is used, serve it locally; if that is too heavy, use
plain tables/CSS/canvas for the MVP dashboard.

## Risks and unknowns

- `yfinance` is an unofficial/fragile market-data source. Mitigation: isolate it behind
  `MarketDataSource`, cache quote snapshots, and surface stale/error state in `/health` and the UI.
- The system-design table says event rows carry `voided_by`, but true append-only correction means
  runtime reads should derive that field from correction events. This needs careful implementation
  and likely a small doc clarification once tests prove the shape.
- Weighted-average cost and export rounding can drift if floats enter the domain. Use `Decimal`
  everywhere for BRL/USD math and assert exact fixture values.
- Tax/compliance numbers remain provisional. Do not encode tax liability logic; only record and
  roll up the fields required by `compliance-tax.md`.
- Threshold flags are included in the Phase 1 export summary because the golden fixture asserts
  them. Proactive threshold alerting remains deferred.
- Charting library choice may collide with local-first/no-build constraints. The dashboard must not
  depend on an internet CDN; use local static assets or simpler rendering.
- Market-hours-aware polling is useful but not required for the red-first export path. Build manual
  refresh/cache first, then add APScheduler only after ledger/export tests are stable.
- The app will store personal financial data in SQLite. Keep the DB path gitignored and document
  backup/encryption expectations in README without turning this into hosted security work.

## Research / citations

- `docs/specs/001-foundation/spec.md` - source contract, phase scope, D8-D12 debate outcomes.
- `docs/specs/001-foundation/fixtures/golden-ledger.md` - executable export oracle.
- `docs/system-design.md` - stack, adapter boundaries, ledger tables, append-only decisions.
- `docs/compliance-tax.md` - obligation-to-field map and tax-boundary posture.
- `docs/prd/v1.md` - P0 user stories and release scope.
- FastAPI static files documentation - `https://fastapi.tiangolo.com/tutorial/static-files`.
- yfinance `Ticker.fast_info` and ticker history documentation - `https://ranaroussi.github.io/yfinance/reference/api/yfinance.Ticker.fast_info.html`.
- Chart.js browser/script integration documentation - `https://github.com/chartjs/chart.js/blob/master/docs/getting-started/integration.md`.
