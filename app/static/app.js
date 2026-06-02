const positionsBody = document.querySelector("#positions");
const quotesBody = document.querySelector("#quotes");
const eventsBody = document.querySelector("#events");
const yearInput = document.querySelector("#tax-year");
const summaryLink = document.querySelector("#summary-link");
const eventsLink = document.querySelector("#events-link");
const eventType = document.querySelector("#event-type");
const eventPayload = document.querySelector("#event-payload");

const payloadTemplates = {
  remittance: {
    event_id: "r1",
    date: "2026-06-02",
    brl_amount: "33969.60",
    usd_credited: "6000.00",
    fx_rate: "5.60",
    fx_provenance: "broker contract",
    iof: "369.60",
    wire_fee: "0.00",
    source_account: "own CPF",
    broker: "IBKR",
  },
  trade: {
    event_id: "t1",
    date: "2026-06-03",
    ticker: "NVDA",
    market: "US",
    currency: "USD",
    instrument: "STOCK",
    us_situs: true,
    side: "BUY",
    origin: "NORMAL",
    qty: "10",
    unit_price: "100.00",
    commission: "1.00",
    fx_to_brl: "5.60",
    fx_provenance: "broker contract",
  },
  dividend: {
    event_id: "d1",
    date: "2026-09-15",
    ticker: "NVDA",
    gross: "4.00",
    currency: "USD",
    foreign_tax_withheld: "1.20",
    net: "2.80",
    fx_to_brl: "5.75",
    fx_provenance: "broker contract",
  },
  btc_origin: {
    event_id: "x1",
    date: "2026-06-01",
    brl_proceeds: "33600.00",
    acq_cost_brl: "12000.00",
    gain_brl: "21600.00",
    exempt_35k: true,
    in1888_reportable: true,
  },
  year_end_balance: {
    event_id: "y1",
    date: "2026-12-31",
    tax_year: 2026,
    ticker: "NVDA",
    qty: "9",
    price: "140.00",
    price_provenance: "yfinance close",
    fx_rate: "5.50",
    fx_provenance: "PTAX 31/12",
  },
};

function cell(text) {
  const td = document.createElement("td");
  td.textContent = text ?? "";
  return td;
}

function row(values) {
  const tr = document.createElement("tr");
  values.forEach((value) => tr.appendChild(cell(value)));
  return tr;
}

async function refresh() {
  const [dashboardResponse, eventsResponse] = await Promise.all([
    fetch("/api/dashboard"),
    fetch("/api/ledger/events"),
  ]);
  const data = await dashboardResponse.json();
  const events = await eventsResponse.json();
  positionsBody.replaceChildren(
    ...data.positions.map((position) =>
      row([
        position.ticker,
        position.qty,
        position.avg_cost_brl,
        position.cost_basis_brl,
        position.market_value_usd,
        position.unrealized_pl_brl,
        `${position.portfolio_weight_pct}%`,
      ]),
    ),
  );
  document.querySelector("#category-change").textContent = `${data.category.avg_day_change_pct}%`;
  quotesBody.replaceChildren(
    ...data.quotes.map((quote) =>
      row([quote.ticker, quote.price, `${quote.day_change_pct}%`, quote.currency, quote.ts]),
    ),
  );
  eventsBody.replaceChildren(
    ...events.map((event) =>
      row([
        event.id,
        event.event_type,
        event.date,
        event.ticker,
        event.side,
        event.voided_by,
      ]),
    ),
  );
}

function updateExportLinks() {
  const year = yearInput.value;
  summaryLink.href = `/api/export/${year}/summary`;
  eventsLink.href = `/api/export/${year}/events.csv`;
}

document.querySelector("#refresh").addEventListener("click", refresh);
document.querySelector("#refresh-quotes").addEventListener("click", async () => {
  await fetch("/api/quotes/refresh", { method: "POST" });
  await refresh();
});
yearInput.addEventListener("input", updateExportLinks);
eventType.addEventListener("change", () => {
  eventPayload.value = JSON.stringify(payloadTemplates[eventType.value], null, 2);
});
document.querySelector("#event-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const payload = JSON.parse(eventPayload.value);
  payload.event_type = eventType.value;
  await fetch("/api/ledger/events", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  await refresh();
});
document.querySelector("#correction-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const target = document.querySelector("#correction-target").value;
  await fetch(`/api/ledger/events/${target}/correct`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      correction_id: document.querySelector("#correction-id").value,
      date: document.querySelector("#correction-date").value,
      reason: document.querySelector("#correction-reason").value,
    }),
  });
  await refresh();
});
eventPayload.value = JSON.stringify(payloadTemplates[eventType.value], null, 2);
updateExportLinks();
refresh();
