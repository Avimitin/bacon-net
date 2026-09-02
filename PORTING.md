# Porting guide: MonkeyBusiness (Python/FastAPI) → bacon-net (Elixir/Plug)

Every Python module under `modules/` maps to one Elixir module under
`lib/bacon_net/modules/<game>/<file>.ex`. Keep handler names, DB tables,
field names, and response shapes byte-identical to the Python originals.

## Module skeleton

```elixir
defmodule BaconNet.Modules.Iidx.Iidx33pc do
  @moduledoc "Port of modules/iidx/iidx33pc.py."

  alias BaconNet.{Config, Core, DB, E, XNode}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"IIDX33pc", "get", :iidx33pc_get},
        {"game", "sv{ver}_load", :game_sv_load}   # versioned route -> fun/2
      ],
      # optional JSON API (api_*.py):
      api: [
        {:get, ["profiles"], :profiles},
        {:get, ["profiles", :iidx_id], :profile},
        {:patch, ["profiles", :iidx_id], :profile_patch},
        {:post, ["parse_mdb", "upload"], :parse_mdb_upload}
      ]
    }
  end

  def iidx33pc_get(conn) do
    {info, conn} = Core.process_request(conn)
    node = Core.module_node(info)            # request_info["root"][0]
    cid = XNode.attr(node, "rid")            # node.attrib["rid"]

    response = E.e("response", E.e("pc", ...))
    Core.send_response(conn, info, response)
  end

  # versioned handler (route contains {ver}); called as game_sv_load(conn, "6")
  def game_sv_load(conn, ver) do ... end
end
```

* `prefix`/`tag` come from the Python `APIRouter(prefix=..., tags=[...])`.
* Each `@router.post("/{gameinfo}/<mod>/<method>")` becomes one
  `{mod, method, fun_name}` handler. `fun_name` is the Python function name
  verbatim (lowercase already).
* Routes containing `{ver}` (sdvx `sv{ver}_*`, gitadora `{ver}_shopinfo`)
  produce handlers of arity 2: `(conn, ver)`.
* Register the module in `BaconNet.Registry` `@modules`.

## Request access patterns

| Python                                        | Elixir |
|-----------------------------------------------|--------|
| `request_info["root"].attrib["srcid"]`        | `XNode.attr(info.root, "srcid")` |
| `request_info["root"][0].attrib["rid"]`       | `Core.module_node(info) \|> XNode.attr("rid")` |
| `request_info["root"][0].find("cardid").text` | `node \|> XNode.child("cardid") \|> Map.get(:text)` |
| `request_info["model"]` / `"method"` / `"game_version"` | `info.model` / `info.method` / `info.game_version` |
| `int(...)` on attr/text                       | `String.to_integer(...)` or `XNode.attr_int(node, "x")` |
| `request.client.host`                         | `conn.remote_ip \|> :inet.ntoa() \|> to_string()` |

## Building responses (E builder)

| Python | Elixir |
|--------|--------|
| `E.response(E.pc(...))` | `E.e("response", E.e("pc", ...))` |
| `E.pcdata(dach=1, name="ＤＪ")` | `E.e("pcdata", dach: 1, name: "ＤＪ")` |
| `E.result(0, __type="u8")` | `E.e("result", 0, __type: "u8")` |
| `E.flg1([-1, -1], __type="s64")` | `E.e("flg1", [-1, -1], __type: "s64")` |
| `E("id", "EA000001", __type="str")` | `E.e("id", "EA000001", __type: "str")` |
| `E.eaappli(E.relation(1, __type="s8"))` | `E.e("eaappli", E.e("relation", 1, __type: "s8"))` |
| `E.services(expire=10800, *items)` | `E.e("services", items, expire: 10800)` (children list as 2nd arg) |
| `E.item(name=k, url=v)` | `E.e("item", name: k, url: v)` |

* Reserved option keys: `:__type`, `:__count`, `:__size` (kbin type hints).
  All other option keys become attributes.
* Values: integers/bools/floats are stringified like the Python typemap
  (`true → "1"`, `false → "0"`).
* If an attribute is literally named `type`, write `type: v` — it does not
  collide with the reserved `:__type`.

## Database (TinyDB → BaconNet.DB)

| Python | Elixir |
|--------|--------|
| `get_db().table("t").get(where("f") == v)` | `DB.get("t", %{"f" => v})` |
| `get_db().table("t").search((where("a") == x) & (where("b") == y))` | `DB.search("t", %{"a" => x, "b" => y})` |
| `get_db().table("t").all()` | `DB.all("t")` |
| `get_db().table("t").insert(doc)` | `DB.insert("t", doc)` |
| `get_db().table("t").upsert(doc, where("card") == c)` | `DB.upsert("t", doc, %{"card" => c})` |
| `get_db().table("t").update(fields, cond)` | `DB.update("t", fields, cond)` |
| `get_db().table("t").remove(cond)` | `DB.remove("t", cond)` |

Documents are maps with string keys, exactly like the TinyDB JSON.
`profile.get("key", default)` → `Map.get(profile, "key", default)`.

## Misc Python → Elixir

* `config.arcade` etc. → `Config.arcade()` etc.
* `int(time.time())` → `:os.system_time(:second)`
* `random.randint(a, b)` → `:rand.uniform(b - a + 1) + a - 1`
* `random.choice(list)` → `Enum.random(list)`
* Module-level mutable globals → `BaconNet.State` (see eacoin.ex)
* `f"{x:08d}"` → `:io_lib.format("~8.8.0d", [x]) |> IO.iodata_to_binary()`
* `str.split(" ")` → `String.split(" ", trim: true)`
* JSON API handlers: `fun.(conn, params)` returns conn; respond with
  `BaconNet.Api.json(conn, data)`. PATCH bodies arrive parsed in
  `conn.body_params` (Plug.Parsers).

## Verification

Compile with `nix develop --command mix compile`. All modules must compile
warning-free. Do not weaken types or skip fields to silence errors — match
the Python behavior.
