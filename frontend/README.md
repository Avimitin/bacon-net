# bacon-net webui

Multi-user web frontend for the bacon-net e-amusement server: player accounts,
card binding, per-game profile settings, personal scores, server-wide rankings,
plus an operator admin area for raw table access.

Pure static single-page app — Vite + vanilla ES modules, no UI frameworks, no
CDN assets, `vite` is the only npm dependency (devDependency).

Node.js/npm come from Nix — run all npm commands from the repo root:

```sh
cd /root/jiongjia-workspace/bacon-net && nix develop --command npm --prefix frontend <args>
```

## Development

```sh
nix develop --command npm --prefix frontend install
nix develop --command npm --prefix frontend run dev
```

Open http://localhost:5173/webui/ with the Elixir server on port 8000. The dev
server proxies `/account`, `/manage`, and `/config` to `http://localhost:8000`.

## Build

```sh
nix develop --command npm --prefix frontend run build
```

Outputs a self-contained static site to `frontend/dist/` with `base: "/webui/"`.

## Views

Hash-routed; unauthenticated users only reach `#/login` and `#/register`; any
401 from the account API clears the session and returns to `#/login`.

- `#/login`, `#/register` — account auth; register can optionally bind a first
  card right after signup. Server error codes are shown as human messages.
- `#/` — dashboard: greeting, bound cards, and a panel per owned game profile
  (game name from `GET /account/api/games`, player name, game ID, versions,
  masked PIN, link into the settings editor).
- `#/cards` — bind cards by UID (E004…) or Konami ID, unbind with confirm; each
  card lists the game profiles attached to it. Konami IDs are only returned at
  bind time, so they are cached in `localStorage` for display.
- `#/settings/{table}/{doc_id}` — profile editor. Quick-edit name + PIN; version
  tabs; curated labeled form for IIDX per-version settings (toggles, numbers,
  selects) plus an "Advanced" validated raw-JSON editor per version (used alone
  for other games). Only changed top-level fields are PATCHed; since the server
  merges top-level only, a change to `version.<ver>.<field>` sends the entire
  client-side-merged `version` map.
- `#/scores` — game tabs (only games with rows), history/best toggle from the
  games metadata, substring filter, rows sorted by song then score descending,
  per-game columns from `src/schema.js` with badges for clear/lamp/rank/grade.
- `#/rankings` — game/table selector, entries grouped under song headers,
  rank medals for 1–3, rows owned by the current user highlighted.
- `#/admin` — operator area. Admin bearer token prompt (stored separately in
  `localStorage`), then tables list with counts + drop, per-table document
  browser with JSON substring filter and create, and a JSON document editor
  with live validation (PUT save, PATCH merge, delete). A 401 clears the
  stored token and re-prompts.

## Layout

```
src/api.js      fetch wrapper, player session + admin token storage, games metadata cache
src/ui.js       el() builder, badges, validated jsonField, table builder, formatting
src/schema.js   per-game score columns, curated IIDX settings fields
src/views/      auth, dashboard, cards, settings, scores, rankings, admin
src/main.js     hash router, auth guard, shell (sticky glass nav, user chip, logout)
src/style.css   neon arcade theme: aurora blobs, glassmorphism panels, glow accents
```

All rendering is XSS-safe (textContent / createTextNode only).
