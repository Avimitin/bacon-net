// API layer: player session (HttpOnly cookie), admin token, game metadata,
// typed fetch wrapper.
//
// Player auth rides on the `bacon_session` HttpOnly cookie set by
// /account/api/login (and /register). The token itself is never stored in
// the browser: non-browser clients can still send `Authorization: Bearer`
// (login keeps returning it in the JSON body). Cookie-authenticated
// mutations must carry the X-CSRF-Requested-With header; we send it on
// every non-GET request, which header-authenticated requests tolerate.

const ADMIN_KEY = "bn.admin";
const KONAMI_KEY = "bn.konami";

export class ApiError extends Error {
  constructor(status, code) {
    super(code || `HTTP ${status}`);
    this.status = status;
    this.code = code || null;
    this.admin = false; // set when the request used the admin token
  }
}

export const tokens = {
  get admin() {
    return localStorage.getItem(ADMIN_KEY) || null;
  },
  set admin(token) {
    if (token) localStorage.setItem(ADMIN_KEY, token);
    else localStorage.removeItem(ADMIN_KEY);
  },
};

// Konami IDs are only returned at bind time; remember them per card uid.
export const konamiCache = {
  all() {
    try {
      return JSON.parse(localStorage.getItem(KONAMI_KEY)) || {};
    } catch {
      return {};
    }
  },
  get(uid) {
    return this.all()[uid] || null;
  },
  set(uid, konamiId) {
    if (!uid || !konamiId) return;
    const map = this.all();
    map[uid] = konamiId;
    localStorage.setItem(KONAMI_KEY, JSON.stringify(map));
  },
  remove(uid) {
    const map = this.all();
    delete map[uid];
    localStorage.setItem(KONAMI_KEY, JSON.stringify(map));
  },
};

const enc = encodeURIComponent;

async function request(path, { method = "GET", body, token, admin = false, signal } = {}) {
  const headers = {};
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (token) headers["Authorization"] = `Bearer ${token}`;
  // CSRF guard for cookie-authenticated mutations (exempt for header auth).
  if (method !== "GET") headers["X-CSRF-Requested-With"] = "fetch";
  const res = await fetch(path, {
    method,
    headers,
    credentials: "same-origin",
    signal,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  if (res.status === 204) return null;
  let data = null;
  try {
    data = await res.json();
  } catch {
    /* non-JSON body */
  }
  if (!res.ok) {
    const err = new ApiError(res.status, data && data.error);
    err.admin = admin;
    throw err;
  }
  return data;
}

const playerCall = (path, opts = {}) => request(path, opts);
const adminCall = (path, opts = {}) =>
  request(path, { ...opts, token: tokens.admin, admin: true });

const query = (params) => {
  const q = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== "") q.set(key, value);
  }
  const s = q.toString();
  return s ? `?${s}` : "";
};

export const api = {
  // ---- account / player ----
  register: (username, password) =>
    request("/account/api/register", { method: "POST", body: { username, password } }),
  login: (username, password) =>
    request("/account/api/login", { method: "POST", body: { username, password } }),
  logout: () => playerCall("/account/api/logout", { method: "POST" }),
  games: () => request("/account/api/games"),
  me: () => playerCall("/account/api/me"),
  bindCard: (card) => playerCall("/account/api/cards", { method: "POST", body: { card } }),
  unbindCard: (uid) => playerCall(`/account/api/cards/${enc(uid)}`, { method: "DELETE" }),
  profiles: () => playerCall("/account/api/profiles"),
  profile: (table, docId) => playerCall(`/account/api/profiles/${enc(table)}/${enc(docId)}`),
  patchProfile: (table, docId, patch) =>
    playerCall(`/account/api/profiles/${enc(table)}/${enc(docId)}`, {
      method: "PATCH",
      body: patch,
    }),
  myScores: ({ limit, cursor, signal } = {}) =>
    playerCall(`/account/api/scores${query({ limit, cursor })}`, { signal }),
  rankings: ({ game, song, chart, limit, signal }) =>
    playerCall(`/account/api/rankings${query({ game, song, chart, limit })}`, { signal }),

  // ---- admin (operator token) ----
  config: () => request("/config"),
  tables: () => adminCall("/manage/api/tables"),
  cardsAll: () => adminCall("/manage/api/cards"),
  docs: (table) => adminCall(`/manage/api/table/${enc(table)}`),
  doc: (table, id) => adminCall(`/manage/api/table/${enc(table)}/${enc(id)}`),
  create: (table, data) =>
    adminCall(`/manage/api/table/${enc(table)}`, { method: "POST", body: data }),
  replace: (table, id, data) =>
    adminCall(`/manage/api/table/${enc(table)}/${enc(id)}`, { method: "PUT", body: data }),
  patch: (table, id, data) =>
    adminCall(`/manage/api/table/${enc(table)}/${enc(id)}`, { method: "PATCH", body: data }),
  deleteDoc: (table, id) =>
    adminCall(`/manage/api/table/${enc(table)}/${enc(id)}`, { method: "DELETE" }),
  dropTable: (table) => adminCall(`/manage/api/table/${enc(table)}`, { method: "DELETE" }),

  // ---- admin: shops (permitted cabinet PCBIDs) ----
  shops: () => adminCall("/manage/api/shops"),
  createShop: (pcbid, opname) =>
    adminCall("/manage/api/shops", {
      method: "POST",
      body: opname ? { pcbid, opname } : { pcbid },
    }),
  permitShop: (pcbid) => adminCall(`/manage/api/shops/${enc(pcbid)}/permit`, { method: "POST" }),
  revokeShop: (pcbid) => adminCall(`/manage/api/shops/${enc(pcbid)}/revoke`, { method: "POST" }),
  deleteShop: (pcbid) => adminCall(`/manage/api/shops/${enc(pcbid)}`, { method: "DELETE" }),

  // ---- admin: users ----
  users: () => adminCall("/manage/api/users"),
  banUser: (username) => adminCall(`/manage/api/users/${enc(username)}/ban`, { method: "POST" }),
  unbanUser: (username) =>
    adminCall(`/manage/api/users/${enc(username)}/unban`, { method: "POST" }),

  // ---- admin: audit trail ----
  audit: ({ limit, cursor } = {}) => adminCall(`/manage/api/audit${query({ limit, cursor })}`),
};

// ---- game metadata (public, cached) ----

let gamesPromise = null;

export function getGames() {
  gamesPromise ??= api
    .games()
    .then((d) => d.games)
    .catch((error) => {
      // A failed metadata request must not poison every later retry.
      gamesPromise = null;
      throw error;
    });
  return gamesPromise;
}

export function gameForProfileTable(games, table) {
  return games.find((g) => g.profile_table === table) || null;
}

export function scoreTableMeta(games, gameKey, table) {
  const game = games.find((g) => g.key === gameKey);
  return game?.score_tables?.find((t) => t.table === table) || null;
}
