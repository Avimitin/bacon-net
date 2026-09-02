# bacon-net

Experimental e-amusement server intended for testing hacks, also usable by
players — an Elixir rewrite of [MonkeyBusiness](https://github.com/drmext/MonkeyBusiness).

Monorepo layout:

- `/` — Elixir server (Bandit/Plug, no Phoenix); game protocol, JSON APIs,
  TinyDB-compatible store
- `frontend/` — pure static webui (Vite + vanilla JS) for browsing and
  editing user data, served by the server under `/webui`

All binary dependencies (Elixir, Erlang/OTP, Node.js/npm, mix/hex tooling)
are managed by [Nix](https://nixos.org/) via the included flake; only a
working `nix` command is required.

## Usage

Development server (hot toolchain, port 8000):

```sh
nix develop
mix run --no-halt
```

or without entering the shell:

```sh
./start.sh
```

Release build (fully Nix-managed, offline after first fetch; the webui in
`frontend/` is built and bundled in automatically):

```sh
nix build
./result/bin/bacon_net start
```

The built-in web interface for managing user data lives at
`http://localhost:8000/webui/` (see `frontend/README.md` for development).

## Configuration

Defaults match `config.py` from the Python project (see `config/config.exs`).
In releases, override via environment (`config/runtime.exs`):

| Variable                     | Default              |
| ---------------------------- | -------------------- |
| `BACON_PORT`                 | `8000`               |
| `BACON_IP`                   | auto-detected        |
| `BACON_ARCADE`               | `Ｍ０ＮＫＹＢＵＳ１Ｎ３Ｚ` |
| `BACON_PASELI`               | `10000`              |
| `BACON_VERBOSE_LOG`          | `1` (`0` disables)   |
| `BACON_RESPONSE_COMPRESSION` | `0` (`1` enables)    |
| `BACON_MAINTENANCE_MODE`     | `0` (`1` enables)    |
| `BACON_WEBUI_DIR`            | bundled webui        |

The database is a TinyDB-compatible `db.json` in the working directory.

## Management API

REST API backing the webui (also usable standalone; JSON in/out, no auth —
bind to localhost or firewall accordingly):

- `GET /manage/api/tables` — every DB table with document counts
- `GET /manage/api/cards` — all documents with a `card` field, grouped by card
- `GET /manage/api/table/{table}` / `POST` (insert)
- `GET /manage/api/table/{table}/{id}` / `PUT` (replace) / `PATCH` (merge) / `DELETE`
- `DELETE /manage/api/table/{table}` — drop a whole table

Documents are returned with their TinyDB id inlined as `_id`.

## Playable Games

- IIDX 18-20, 29-33 (Online Arena/BPL support)
- DDR A20P, A3, WORLD (OmniMIX/GF, BPL, and Fake PFREE support)
- GD 6-10 DELTA (Battle Mode support)
- DRS
- NOST 3
- SDVX 6-7

**Note**: Playable means settings/scores *should* save and load. Events are
not implemented.

## Tools (mix tasks)

- `mix mdb --input music_data.bin --output songs.json --extract`
  (`--create`, `--merge [--diff]`) — music_data.bin tool
- `mix import.iidx_automap --automap_xml X --version 30 --monkey_db db.json --iidx_id N`
- `mix import.ddr_automap --automap_xml X --version 3 --monkey_db db.json --ddr_id N`
- `mix db.trim [db.json]`

## Development

```sh
nix develop
mix test                              # unit tests (incl. kbinxml golden vectors)
mix run --no-halt                     # dev server
elixir -pa _build/dev/lib/bacon_net/ebin -pa _build/dev/lib/jason/ebin \
  scripts/smoke_test.exs              # end-to-end checks for all seven games
```

Frontend development (Node/npm come from the same `nix develop` shell):

```sh
cd frontend
npm install
npm run dev                           # vite dev server, proxies /manage + /config to :8000
npm run build                         # static build into frontend/dist
```

To serve a fresh frontend build from the dev server, copy it into place:
`cp -r frontend/dist/* priv/static/` (releases do this automatically).

`PORTING.md` documents the Python→Elixir architecture mapping for contributors.

## Troubleshooting

- DRS, GD, NOST, and SDVX require mdb xml files copied to the server folder
- **URL Slash 1 (On)** may be required in rare cases; **URL Slash 0 (Off)**
  in others (the server supports both, like the original)
- When initially creating a DDR profile, complete an entire credit without
  pfree hacks
