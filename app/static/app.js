const positionsBody = document.querySelector("#positions");
const quotesBody = document.querySelector("#quotes");
const eventsBody = document.querySelector("#events");
const yearInput = document.querySelector("#tax-year");
const summaryLink = document.querySelector("#summary-link");
const eventsLink = document.querySelector("#events-link");
const eventType = document.querySelector("#event-type");
const eventFields = document.querySelector("#event-fields");

// Declarative field schemas — one entry per ledger event_type. `kind` drives both the
// rendered control and how the value is serialized for the API:
//   text/date/select/decimal -> kept as a STRING (decimals must stay strings so the
//     backend's Decimal(str(value)) keeps exact precision — never send JS numbers).
//   int  -> serialized with Number().
//   bool -> a checkbox, serialized as a real JSON boolean (backend does int(value)).
// Fields with `required` map to the HTML required attribute; optional fields are
// omitted from the payload when left blank so backend defaults apply.
const FIELD_SCHEMAS = {
  remittance: [
    { name: "event_id", label: "Event ID", kind: "text", required: true },
    { name: "date", label: "Date", kind: "date", required: true },
    { name: "brl_amount", label: "BRL amount", kind: "decimal", required: true },
    { name: "usd_credited", label: "USD credited", kind: "decimal", required: true },
    { name: "fx_rate", label: "FX rate (BRL/USD)", kind: "decimal", required: true },
    { name: "fx_provenance", label: "FX provenance", kind: "text", required: true },
    { name: "iof", label: "IOF", kind: "decimal", default: "0.00" },
    { name: "wire_fee", label: "Wire fee", kind: "decimal", default: "0.00" },
    { name: "source_account", label: "Source account", kind: "text" },
    { name: "broker", label: "Broker", kind: "text" },
    { name: "notes", label: "Notes", kind: "text" },
  ],
  trade: [
    { name: "event_id", label: "Event ID", kind: "text", required: true },
    { name: "date", label: "Date", kind: "date", required: true },
    { name: "ticker", label: "Ticker", kind: "text", required: true },
    { name: "market", label: "Market", kind: "text", required: true, default: "US" },
    { name: "currency", label: "Currency", kind: "text", required: true, default: "USD" },
    { name: "instrument", label: "Instrument", kind: "text", required: true, default: "STOCK" },
    { name: "us_situs", label: "US situs", kind: "bool", default: true },
    { name: "side", label: "Side", kind: "select", options: ["BUY", "SELL"], required: true },
    {
      name: "origin",
      label: "Origin",
      kind: "select",
      options: ["NORMAL", "OPENING_IMPORT"],
      required: true,
      default: "NORMAL",
    },
    { name: "qty", label: "Qty", kind: "decimal", required: true },
    { name: "unit_price", label: "Unit price", kind: "decimal", required: true },
    { name: "commission", label: "Commission", kind: "decimal", required: true, default: "0.00" },
    { name: "fx_to_brl", label: "FX to BRL", kind: "decimal", required: true },
    { name: "fx_provenance", label: "FX provenance", kind: "text", required: true },
    { name: "basis_provenance", label: "Basis provenance", kind: "text" },
    { name: "linked_remittance_id", label: "Linked remittance ID", kind: "text" },
    { name: "notes", label: "Notes", kind: "text" },
  ],
  dividend: [
    { name: "event_id", label: "Event ID", kind: "text", required: true },
    { name: "date", label: "Date", kind: "date", required: true },
    { name: "ticker", label: "Ticker", kind: "text", required: true },
    { name: "gross", label: "Gross", kind: "decimal", required: true },
    { name: "currency", label: "Currency", kind: "text", required: true, default: "USD" },
    { name: "foreign_tax_withheld", label: "Foreign tax withheld", kind: "decimal", required: true },
    { name: "net", label: "Net", kind: "decimal", required: true },
    { name: "fx_to_brl", label: "FX to BRL", kind: "decimal", required: true },
    { name: "fx_provenance", label: "FX provenance", kind: "text", required: true },
    { name: "notes", label: "Notes", kind: "text" },
  ],
  btc_origin: [
    { name: "event_id", label: "Event ID", kind: "text", required: true },
    { name: "date", label: "Date", kind: "date", required: true },
    { name: "brl_proceeds", label: "BRL proceeds", kind: "decimal", required: true },
    { name: "acq_cost_brl", label: "Acquisition cost BRL", kind: "decimal", required: true },
    { name: "gain_brl", label: "Gain BRL", kind: "decimal", required: true },
    { name: "exempt_35k", label: "Exempt (35k/mo)", kind: "bool", default: true },
    { name: "in1888_reportable", label: "IN 1888 reportable", kind: "bool", default: true },
    { name: "notes", label: "Notes", kind: "text" },
  ],
  year_end_balance: [
    { name: "event_id", label: "Event ID", kind: "text", required: true },
    { name: "date", label: "Date", kind: "date", required: true },
    { name: "tax_year", label: "Tax year", kind: "int", required: true },
    { name: "ticker", label: "Ticker", kind: "text", required: true },
    { name: "qty", label: "Qty", kind: "decimal", required: true },
    { name: "price", label: "Price", kind: "decimal", required: true },
    { name: "price_provenance", label: "Price provenance", kind: "text", required: true },
    { name: "fx_rate", label: "FX rate (BRL/USD)", kind: "decimal", required: true },
    { name: "fx_provenance", label: "FX provenance", kind: "text", required: true },
    { name: "notes", label: "Notes", kind: "text" },
  ],
};

function fieldControl(field) {
  if (field.kind === "bool") {
    const input = document.createElement("input");
    input.type = "checkbox";
    input.checked = field.default === true;
    return input;
  }
  if (field.kind === "select") {
    const select = document.createElement("select");
    field.options.forEach((option) => {
      const el = document.createElement("option");
      el.value = option;
      el.textContent = option;
      select.appendChild(el);
    });
    select.value = field.default ?? field.options[0];
    return select;
  }
  const input = document.createElement("input");
  input.type = field.kind === "date" ? "date" : "text";
  if (field.kind === "decimal" || field.kind === "int") {
    input.inputMode = "decimal";
  }
  if (field.default !== undefined) {
    input.value = field.default;
  }
  if (field.required) {
    input.required = true;
  }
  return input;
}

function renderEventFields(type) {
  const controls = FIELD_SCHEMAS[type].map((field) => {
    const control = fieldControl(field);
    control.dataset.name = field.name;
    control.dataset.kind = field.kind;
    const label = document.createElement("label");
    if (field.kind === "bool") {
      label.classList.add("checkbox-row");
    }
    label.append(field.label, control);
    return label;
  });
  eventFields.replaceChildren(...controls);
}

function buildEventPayload() {
  const payload = { event_type: eventType.value };
  eventFields.querySelectorAll("[data-name]").forEach((control) => {
    const { name, kind } = control.dataset;
    if (kind === "bool") {
      payload[name] = control.checked;
      return;
    }
    const value = control.value.trim();
    if (value === "") {
      return; // omit blank optionals so backend defaults apply
    }
    payload[name] = kind === "int" ? Number(value) : value;
  });
  return payload;
}

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
  renderEventFields(eventType.value);
});
document.querySelector("#event-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  await fetch("/api/ledger/events", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(buildEventPayload()),
  });
  renderEventFields(eventType.value); // clear fields to defaults, keep selected type
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
renderEventFields(eventType.value);
updateExportLinks();
refresh();
