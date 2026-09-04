# bacon-net webui

Multi-user web frontend for the bacon-net e-amusement server: player accounts,
card binding, per-game profile settings, personal scores, server-wide rankings,
plus an operator admin area (shops, users, raw table access).

React single-page app built with Vite, routed with `react-router` (HashRouter),
with Carbon Design System components (`@carbon/react`, `@carbon/icons-react`)
providing the interaction and accessibility foundation. The `g100` shell and
`g10` content canvas use the custom **Signal Grid** composition layer documented
in [`docs/frontend-design-language.md`](../docs/frontend-design-language.md).

Node.js/npm come from Nix — run all npm commands from the repo root:

```sh
nix develop --command npm --prefix frontend <args>
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

- `/login`, `/register` — full-bleed account access surfaces paired with the
  account → card → play network model. Registration can optionally bind a first
  card and offers a "continue anyway" path if that second step fails. Server
  error codes are shown as human messages, including `account_banned`.
- `/` — dashboard: a live account → card → profile topology, bounded account
  summary, profile matrix, and secondary access-card rail. Each profile links
  to its settings and keeps only the task-relevant player ID and versions in
  view; cached Konami IDs remain in the card rail.
- `/cards` — an access ledger for binding by UID (E004…) or Konami ID and
  unbinding through a compact confirmation `Modal`. Each card exposes its
  attached profiles as direct settings links. Konami IDs are only returned at
  bind time, so they are cached in `localStorage` for display.
- `/settings/:table/:docId` — profile editor with a connected-game identity
  strip, quick-edit name + PIN, version `Tabs`, and a change-status action
  rail. IIDX gets curated `Toggle`, `Dropdown`, and `NumberInput` controls from
  `IIDX_FIELDS`; every game retains an advanced validated JSON `TextArea`.
  Since the server merges top-level only, changing `version.<ver>.<field>` sends
  the entire client-side-merged `version` map.
- `/scores` — chronological score archive with URL-backed game and substring
  filters, a schema-derived Carbon `DataTable`, and cursor-backed pagination.
  Filters intentionally apply only to the current server-loaded page.
- `/rankings` — a four-coordinate game/song/chart/limit query with suggestions
  from the player's own records and a ranked `DataTable`; a "you" status `Tag`
  identifies rows owned by the current player.
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
  - **Audit** — cursor-paginated administrative mutations with actor, target,
    outcome, and request ID.

Every route follows the 4/8/16-column Signal Grid and uses one page `h1`;
data-backed routes also preserve their geometry across loading, empty, and error
states. The tracked screenshot runner checks public and authenticated routes at
1440, 800, and 390 pixels, including page overflow, landmarks, heading
structure, mobile navigation, and a narrow modal.

## Layout

```
src/api.js      fetch wrapper, player session + admin token storage, games metadata cache
src/app.css     Signal Grid shell, every route composition, and 2x Grid tokens
src/components/ shared SignalHero, SectionHeading, auth frame, and route states
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
