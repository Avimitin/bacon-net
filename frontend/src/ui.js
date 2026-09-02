// Shared UI primitives: element builder, badges, validated JSON field, tables, formatting.

export function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (value == null) continue;
    if (key === "class") node.className = value;
    else if (key === "dataset") Object.assign(node.dataset, value);
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value);
  }
  for (const child of children.flat(Infinity)) {
    if (child == null || child === false) continue;
    node.append(child.nodeType ? child : document.createTextNode(String(child)));
  }
  return node;
}

export function link(hash, ...children) {
  return el("a", { href: hash }, ...children);
}

const ERROR_MESSAGES = {
  invalid_username: "Usernames are 3–24 chars: lowercase a–z, digits, underscore.",
  password_too_short: "Password must be at least 8 characters.",
  username_taken: "That username is already taken.",
  invalid_credentials: "Wrong username or password.",
  invalid_card: "That card UID / Konami ID is not valid.",
  card_already_bound: "This card is already bound to your account.",
  card_bound_to_other_account: "This card is bound to a different account.",
  unauthorized: "Session expired — please log in again.",
  not_found: "Not found.",
};

export function humanError(err) {
  return ERROR_MESSAGES[err.code] || err.message || "Something went wrong.";
}

export function errorBox(err) {
  return el("div", { class: "error-box" }, humanError(err));
}

export function emptyState(text, hint) {
  return el(
    "div",
    { class: "empty-state" },
    el("p", { class: "empty-title" }, text),
    hint ? el("p", { class: "muted" }, hint) : null
  );
}

export function skeleton(lines = 3) {
  return el(
    "div",
    { class: "panel skeleton-wrap" },
    ...Array.from({ length: lines }, (_, i) =>
      el("div", { class: "skeleton", style: `width:${85 - i * 20}%` })
    )
  );
}

export function badge(text, variant = "") {
  return el("span", { class: `badge ${variant}`.trim() }, text);
}

export function fmtTs(ts) {
  if (ts == null || ts === "") return "—";
  const n = Number(ts);
  if (Number.isFinite(n)) {
    const ms = n > 1e12 ? n : n * 1000; // tolerate seconds or ms
    return new Date(ms).toLocaleString(undefined, {
      year: "numeric",
      month: "short",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    });
  }
  const d = new Date(ts);
  return Number.isNaN(d.getTime()) ? String(ts) : d.toLocaleString();
}

export function fmtDate(ts) {
  if (ts == null) return "—";
  const n = Number(ts);
  const d = Number.isFinite(n) ? new Date(n > 1e12 ? n : n * 1000) : new Date(ts);
  return Number.isNaN(d.getTime())
    ? String(ts)
    : d.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "2-digit" });
}

// Validated JSON editor (object-only). validate() returns the parsed object or null.
export function jsonField(labelText, value) {
  const textarea = el("textarea", { class: "json-editor", spellcheck: "false" });
  textarea.value = value;
  const status = el("div", { class: "json-status ok" }, "valid JSON");
  const validate = () => {
    try {
      const parsed = JSON.parse(textarea.value);
      if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
        throw new Error("must be a JSON object");
      }
      status.textContent = "valid JSON";
      status.className = "json-status ok";
      return parsed;
    } catch (err) {
      status.textContent = `invalid JSON: ${err.message}`;
      status.className = "json-status bad";
      return null;
    }
  };
  textarea.addEventListener("input", validate);
  const pretty = el(
    "button",
    {
      class: "btn ghost small",
      type: "button",
      onclick: () => {
        const parsed = validate();
        if (parsed) textarea.value = JSON.stringify(parsed, null, 2);
      },
    },
    "pretty-print"
  );
  validate();
  return {
    field: el(
      "div",
      { class: "json-field" },
      el("div", { class: "json-field-head" }, el("label", {}, labelText), pretty),
      textarea,
      status
    ),
    textarea,
    validate,
  };
}

// columns: [{key, label, kind}] — kinds: text, num, song, ts, badge, bool, pct
export function buildTable(columns, rows) {
  const head = el(
    "tr",
    {},
    ...columns.map((c) => el("th", { class: c.kind === "num" ? "num" : "" }, c.label))
  );
  const body = rows.map((row) =>
    el("tr", {}, ...columns.map((c) => el("td", cellAttrs(c), renderCell(c, row[c.key]))))
  );
  return el(
    "div",
    { class: "table-scroll" },
    el("table", { class: "data" }, el("thead", {}, head), el("tbody", {}, ...body))
  );
}

function cellAttrs(col) {
  return ["num", "song", "ts"].includes(col.kind) ? { class: "num" } : {};
}

function renderCell(col, value) {
  if (value == null || value === "") return document.createTextNode("—");
  switch (col.kind) {
    case "ts":
      return document.createTextNode(fmtTs(value));
    case "badge":
      return badge(String(value), "badge-soft");
    case "bool":
      return el(
        "span",
        { class: value ? "bool on" : "bool off" },
        value ? "✓" : "—"
      );
    case "pct":
      return document.createTextNode(`${value}%`);
    default:
      return document.createTextNode(String(value));
  }
}

export function compare(a, b) {
  const na = Number(a);
  const nb = Number(b);
  if (Number.isFinite(na) && Number.isFinite(nb)) return na - nb;
  return String(a ?? "").localeCompare(String(b ?? ""), undefined, { numeric: true });
}
