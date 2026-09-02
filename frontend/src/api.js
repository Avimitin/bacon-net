const BASE = "";

async function request(path, options = {}) {
  const res = await fetch(BASE + path, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  if (res.status === 204) return null;
  let body = null;
  try {
    body = await res.json();
  } catch {
    /* non-JSON body */
  }
  if (!res.ok) {
    const msg = body && body.error ? body.error : `HTTP ${res.status}`;
    const err = new Error(msg);
    err.status = res.status;
    throw err;
  }
  return body;
}

export const api = {
  config: () => request("/config"),
  tables: () => request("/manage/api/tables"),
  cards: () => request("/manage/api/cards"),
  docs: (table) => request(`/manage/api/table/${encodeURIComponent(table)}`),
  doc: (table, id) =>
    request(`/manage/api/table/${encodeURIComponent(table)}/${encodeURIComponent(id)}`),
  create: (table, data) =>
    request(`/manage/api/table/${encodeURIComponent(table)}`, {
      method: "POST",
      body: JSON.stringify(data),
    }),
  replace: (table, id, data) =>
    request(`/manage/api/table/${encodeURIComponent(table)}/${encodeURIComponent(id)}`, {
      method: "PUT",
      body: JSON.stringify(data),
    }),
  patch: (table, id, data) =>
    request(`/manage/api/table/${encodeURIComponent(table)}/${encodeURIComponent(id)}`, {
      method: "PATCH",
      body: JSON.stringify(data),
    }),
  deleteDoc: (table, id) =>
    request(`/manage/api/table/${encodeURIComponent(table)}/${encodeURIComponent(id)}`, {
      method: "DELETE",
    }),
  dropTable: (table) =>
    request(`/manage/api/table/${encodeURIComponent(table)}`, { method: "DELETE" }),
};
