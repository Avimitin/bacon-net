# bacon-net webui

Multi-user web frontend for the bacon-net e-amusement server: player accounts,
card binding, per-game profile settings, personal scores, server-wide rankings,
plus an operator admin area (shops, users, raw table access).

React single-page app built with Vite, routed with `react-router` (HashRouter),
UI built entirely with Carbon Design System components (`@carbon/react`,
`@carbon/icons-react`) under the `g100` dark theme. No custom theme CSS.

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
The build script sets `IBM_TELEMETRY_DISABLED=true` to disable Carbon's build
telemetry.

## Views

Hash-routed (`/login`, `/register` are public); unauthenticated users are
redirected to `/login`; any 401 from the account API clears the session and
returns to `/login`.

- `/login`, `/register` — account auth; register can optionally bind a first
  card right after signup (with a "continue anyway" path if binding fails).
  Server error codes are shown as human messages, including `account_banned`.
- `/` — dashboard: greeting, bound cards (`Tag`s with cached Konami IDs), and
  a `ClickableTile` per owned game profile (game icon + name, player name,
  game ID, card, masked PIN, version tags, link into the settings editor).
- `/cards` — bind cards by UID (E004…) or Konami ID, unbind with a confirmation
  `Modal`; each card lists the game profiles attached to it. Konami IDs are
  only returned at bind time, so they are cached in `localStorage` for display.
- `/settings/:table/:docId` — profile editor. Quick-edit name + PIN; version
  `Tabs`; curated labeled form for IIDX per-version settings (`Toggle`,
  `Dropdown`, `NumberInput` from `IIDX_FIELDS`) plus an "Advanced" validated
  raw-JSON `TextArea` per version (used alone for other games). Only changed
  top-level fields are PATCHed; since the server merges top-level only, a
  change to `version.<ver>.<field>` sends the entire client-side-merged
  `version` map.
- `/scores` — game `Tabs` (only games with rows), history/best
  `ContentSwitcher` from the games metadata (preferring `best` tables),
  substring `Search` filter over row JSON, Carbon `DataTable` sorted by song
  then score descending, per-game columns from `src/schema.js`.
- `/rankings` — game/table `Dropdown`, entries grouped per song, ranked
  `DataTable`s with a "you" `Tag` on rows owned by the current user.
- `/admin` — operator area. Admin bearer token prompt (stored separately in
  `localStorage` as `bn.admin`, verified against `/manage/api/tables`; a 401
  clears it and re-prompts). Tabs:
  - **Shops** — permitted cabinet PCBIDs: `DataTable` with Permitted/Pending
    `Tag` status, Permit/Revoke/Delete row actions (confirmation `Modal`s),
    and an Add-shop modal.
  - **Users** — user list with banned status and Ban/Unban actions.
  - **Tables** — table list with doc counts and a drop-table danger action.
  - **Docs** — pick a table, browse documents with a JSON substring filter,
    and a JSON document editor with live validation (PUT save, PATCH merge,
    create, delete).
  - **Cards** — grouped card listing from `/manage/api/cards`.

## Layout

```
src/api.js      fetch wrapper, player session + admin token storage, games metadata cache
src/util.js     humanError map, timestamp formatters, compare, JSON-object validation
src/schema.js   per-game score columns, curated IIDX settings fields
src/gameIcons.js game key → bundled icon asset (src/assets/games/)
src/session.jsx SessionProvider (mirrors localStorage), RequireAuth, 401 handler hook
src/views/      Login, Register, Dashboard, Cards, Settings, Scores, Rankings, Admin (.jsx)
src/main.jsx    entry: HashRouter, Carbon Theme (g100), Header shell, route table
```

## Asset credits

Game icons in `src/assets/games/` are from
[bicarus-dev/bemani_fan_site_icons](https://github.com/bicarus-dev/bemani_fan_site_icons).
