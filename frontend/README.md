# bacon-net webui

Pure static single-page app for managing user data in the bacon-net e-amusement
server. Vite + vanilla ES modules, no runtime dependencies (only `vite` as a
devDependency).

Node.js/npm are provided by Nix — run all npm commands from the repo root as:

```sh
nix develop --command npm --prefix frontend <args>
```

## Development

```sh
# install dependencies (creates package-lock.json)
cd /root/jiongjia-workspace/bacon-net && nix develop --command npm --prefix frontend install

# start the dev server (proxies /manage and /config to http://localhost:8000)
cd /root/jiongjia-workspace/bacon-net && nix develop --command npm --prefix frontend run dev
```

Open http://localhost:5173/webui/ with the Elixir server running on port 8000.

## Build

```sh
cd /root/jiongjia-workspace/bacon-net && nix develop --command npm --prefix frontend run build
```

Outputs a fully self-contained static site to `frontend/dist/` with
`base: "/webui/"`, so it can be served as-is under `/webui` by the server.

## Views

- `#/cards` — card grid (card number, player name, links to per-table documents)
- `#/tables` — table list with document counts and drop buttons
- `#/table/{name}` — document list with substring JSON filter and new-document button
- `#/table/{name}/{id}` — JSON editor with live validation, PUT save, PATCH merge,
  delete; `#/table/{name}/new` creates a document via POST
