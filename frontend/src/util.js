// Shared helpers: human error messages, timestamp formatting, sorting, JSON validation.

const ERROR_MESSAGES = {
  invalid_username: "Usernames are 3–24 chars: lowercase a–z, digits, underscore.",
  password_too_short: "Password must be at least 8 characters.",
  username_taken: "That username is already taken.",
  invalid_credentials: "Wrong username or password.",
  account_banned: "This account has been banned.",
  invalid_body: "The request body was invalid.",
  invalid_card: "That card UID / Konami ID is not valid.",
  card_already_bound: "This card is already bound to your account.",
  card_bound_to_other_account: "This card is bound to a different account.",
  shop_exists: "A shop with that PCBID already exists.",
  unauthorized: "Session expired — please log in again.",
  not_found: "Not found.",
};

export function humanError(err) {
  return ERROR_MESSAGES[err?.code] || err?.message || "Something went wrong.";
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

// Numeric-aware compare: numbers numerically, everything else locale-aware.
export function compare(a, b) {
  const na = Number(a);
  const nb = Number(b);
  if (Number.isFinite(na) && Number.isFinite(nb)) return na - nb;
  return String(a ?? "").localeCompare(String(b ?? ""), undefined, { numeric: true });
}

// Parse a JSON-object textarea value. Returns { ok, value, error }.
export function parseJsonObject(text) {
  try {
    const parsed = JSON.parse(text);
    if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
      return { ok: false, value: null, error: "must be a JSON object" };
    }
    return { ok: true, value: parsed, error: null };
  } catch (err) {
    return { ok: false, value: null, error: err.message };
  }
}
