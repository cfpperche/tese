CREATE TABLE IF NOT EXISTS schema_migrations (
  name TEXT PRIMARY KEY,
  applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE TABLE IF NOT EXISTS ledger_events (
  seq INTEGER PRIMARY KEY AUTOINCREMENT,
  id TEXT NOT NULL UNIQUE,
  event_type TEXT NOT NULL CHECK (
    event_type IN ('remittance', 'trade', 'dividend', 'btc_origin', 'year_end_balance', 'correction')
  ),
  date TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  source TEXT NOT NULL DEFAULT 'MANUAL',
  notes TEXT
);

CREATE TABLE IF NOT EXISTS remittance (
  event_id TEXT PRIMARY KEY REFERENCES ledger_events(id),
  brl_amount TEXT NOT NULL,
  usd_credited TEXT NOT NULL,
  fx_rate TEXT NOT NULL,
  fx_provenance TEXT NOT NULL,
  iof TEXT NOT NULL DEFAULT '0.00',
  wire_fee TEXT NOT NULL DEFAULT '0.00',
  source_account TEXT,
  broker TEXT
);

CREATE TABLE IF NOT EXISTS trade (
  event_id TEXT PRIMARY KEY REFERENCES ledger_events(id),
  ticker TEXT NOT NULL,
  market TEXT NOT NULL,
  currency TEXT NOT NULL,
  instrument TEXT NOT NULL,
  us_situs INTEGER NOT NULL DEFAULT 1,
  side TEXT NOT NULL CHECK (side IN ('BUY', 'SELL')),
  origin TEXT NOT NULL DEFAULT 'NORMAL' CHECK (origin IN ('NORMAL', 'OPENING_IMPORT')),
  qty TEXT NOT NULL,
  unit_price TEXT NOT NULL,
  commission TEXT NOT NULL DEFAULT '0.00',
  fx_to_brl TEXT NOT NULL,
  fx_provenance TEXT NOT NULL,
  brl_value TEXT NOT NULL,
  basis_provenance TEXT,
  linked_remittance_id TEXT
);

CREATE TABLE IF NOT EXISTS dividend (
  event_id TEXT PRIMARY KEY REFERENCES ledger_events(id),
  ticker TEXT NOT NULL,
  gross TEXT NOT NULL,
  currency TEXT NOT NULL,
  foreign_tax_withheld TEXT NOT NULL,
  net TEXT NOT NULL,
  fx_to_brl TEXT NOT NULL,
  fx_provenance TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS btc_origin (
  event_id TEXT PRIMARY KEY REFERENCES ledger_events(id),
  brl_proceeds TEXT NOT NULL,
  acq_cost_brl TEXT NOT NULL,
  gain_brl TEXT NOT NULL,
  exempt_35k INTEGER NOT NULL,
  in1888_reportable INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS year_end_balance (
  event_id TEXT PRIMARY KEY REFERENCES ledger_events(id),
  tax_year INTEGER NOT NULL,
  ticker TEXT NOT NULL,
  qty TEXT NOT NULL,
  price TEXT NOT NULL,
  price_provenance TEXT NOT NULL,
  fx_rate TEXT NOT NULL,
  fx_provenance TEXT NOT NULL,
  brl_value TEXT NOT NULL,
  usd_value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS correction (
  event_id TEXT PRIMARY KEY REFERENCES ledger_events(id),
  target_table TEXT NOT NULL,
  target_event_id TEXT NOT NULL REFERENCES ledger_events(id),
  reason TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS instrument_ref (
  ticker TEXT PRIMARY KEY,
  name TEXT,
  market TEXT NOT NULL,
  instrument TEXT NOT NULL,
  us_situs INTEGER NOT NULL,
  thesis_tag TEXT
);

CREATE TABLE IF NOT EXISTS quote_cache (
  ticker TEXT PRIMARY KEY,
  ts TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  price TEXT NOT NULL,
  day_change_pct TEXT NOT NULL,
  currency TEXT NOT NULL
);
