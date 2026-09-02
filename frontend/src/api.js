// API layer: player session, admin token, game metadata, typed fetch wrapper.

const PLAYER_KEY = "bn.player";
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
  get player() {
    try {
      return JSON.parse(localStorage.getItem(PLAYER_KEY));
    } catch {
      return null;
    }
  },
  set player(session) {
    if (session) localStorage.setItem(PLAYER_KEY, JSON.stringify(session));
    else localStorage.removeItem(PLAYER_KEY);
  },
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

async function request(path, { method = "GET", body, token, admin = false } = {}) {
  const headers = {};
  if (body !== undefined) headers["Content-Type"] = "application/json";
  if (token) headers["Authorization"] = `Bearer ${token}`;
  const res = await fetch(path, {
    method,
    headers,
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

const playerCall = (path, opts = {}) =>
  request(path, { ...opts, token: tokens.player?.token });
const adminCall = (path, opts = {}) =>
  request(path, { ...opts, token: tokens.admin, admin: true });

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
  myScores: () => playerCall("/account/api/scores"),
  rankings: () => playerCall("/account/api/rankings"),

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
};

// ---- game metadata (public, cached) ----

let gamesPromise = null;

export function getGames() {
  gamesPromise ??= api.games().then((d) => d.games);
  return gamesPromise;
}

export function gameForProfileTable(games, table) {
  return games.find((g) => g.profile_table === table) || null;
}

export function scoreTableMeta(games, gameKey, table) {
  const game = games.find((g) => g.key === gameKey);
  return game?.score_tables?.find((t) => t.table === table) || null;
}
