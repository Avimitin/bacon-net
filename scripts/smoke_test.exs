# Cross-game smoke test. Requires the server running on :8000.
# Exercises services.get + one or more handlers per game, decoding the kbin
# responses and asserting key fields. Run: mix run scripts/smoke_test.exs

Application.ensure_all_started(:inets)

alias BaconNet.{E, Kbinxml, XNode}

defmodule Smoke do
  @base "http://127.0.0.1:8000"

  def post_kbin(path, model, module_node) do
    body =
      Kbinxml.encode(E.e("call", module_node, model: model, srcid: "A00000000000"))

    {:ok, {{_, status, _}, headers, resp}} =
      :httpc.request(
        :post,
        {String.to_charlist(@base <> path), [{~c"content-type", ~c"application/octet-stream"}],
         ~c"application/octet-stream", body},
        [],
        body_format: :binary
      )

    x_compress = headers |> Enum.find(fn {k, _} -> k == ~c"x-compress" end)

    resp =
      case x_compress do
        {_, ~c"lz77"} -> BaconNet.LZ77.decode(resp)
        _ -> resp
      end

    doc =
      if status == 200 do
        try do
          Kbinxml.decode(resp).node
        rescue
          _ -> nil
        end
      end

    {status, doc}
  end

  def get_json(path) do
    {:ok, {{_, status, _}, _, resp}} =
      :httpc.request(:get, {String.to_charlist(@base <> path), []}, [], body_format: :binary)

    {status, Jason.decode!(resp)}
  end

  def check(name, cond) do
    if cond do
      IO.puts("  ok: #{name}")
    else
      IO.puts("  FAIL: #{name}")
      Process.put(:failures, Process.get(:failures, 0) + 1)
    end
  end
end


card = "E004009999999999"

# --- services.get
IO.puts("services.get")
{st, doc} = Smoke.post_kbin("/core/LDJ:J:A:A:2025091700/services/get", "LDJ:J:A:A:2025091700", E.e("services", method: "get"))
Smoke.check("status 200", st == 200)
services = XNode.child(doc, "services")
items = XNode.children(services, "item") |> Enum.map(&XNode.attr(&1, "name"))
Smoke.check("has core services", Enum.all?(["cardmng", "facility", "pcbtracker"], &(&1 in items)))
Smoke.check("has game services", Enum.all?(["local", "local2", "lobby", "lobby2"], &(&1 in items)))
Smoke.check("has keepalive+ntp", Enum.all?(["keepalive", "ntp"], &(&1 in items)))

# --- IIDX 33
IO.puts("iidx33")
{st, doc} = Smoke.post_kbin("/local/LDJ:J:A:A:2025091700/IIDX33pc/common", "LDJ:J:A:A:2025091700", E.e("IIDX33pc", method: "common"))
Smoke.check("common 200", st == 200 and XNode.child(doc, "IIDX33pc") != nil)

{st, doc} = Smoke.post_kbin("/local/LDJ:J:A:A:2025091700/IIDX33pc/reg", "LDJ:J:A:A:2025091700", E.e("IIDX33pc", method: "reg", cid: card, name: "ＴＥＳＴ", pid: "13"))
Smoke.check("reg 200", st == 200)

{st, doc} = Smoke.post_kbin("/local/LDJ:J:A:A:2025091700/IIDX33pc/get", "LDJ:J:A:A:2025091700", E.e("IIDX33pc", method: "get", cid: card))
Smoke.check("get 200", st == 200)
pc = XNode.child(doc, "IIDX33pc")
Smoke.check("pc has pcdata", XNode.child(pc, "pcdata") != nil)

{st, doc} = Smoke.post_kbin("/local/LDJ:J:A:A:2025091700/IIDX33shop/getname", "LDJ:J:A:A:2025091700", E.e("IIDX33shop", method: "getname"))
Smoke.check("shop getname 200", st == 200)

{st, doc} = Smoke.post_kbin("/local/LDJ:J:A:A:2025091700/IIDX33music/getrank", "LDJ:J:A:A:2025091700", E.e("IIDX33music", method: "getrank", cltype: "0"))
Smoke.check("music getrank 200", st == 200)

{st, doc} = Smoke.post_kbin("/local/LDJ:J:A:A:2025091700/IIDX33gameSystem/systemInfo", "LDJ:J:A:A:2025091700", E.e("IIDX33gameSystem", method: "systemInfo"))
Smoke.check("gameSystem 200", st == 200)

# --- IIDX 29 (local2 prefix)
IO.puts("iidx29")
{st, _doc} = Smoke.post_kbin("/local2/LDJ:J:A:A:2021101300/IIDX29pc/common", "LDJ:J:A:A:2021101300", E.e("IIDX29pc", method: "common"))
Smoke.check("iidx29 common 200", st == 200)

# --- SDVX (versioned routes)
IO.puts("sdvx")
{st, doc} = Smoke.post_kbin("/local2/KFC:J:A:A:2020090402/game/sv6_new", "KFC:J:A:A:2020090402", E.e("game", [E.e("dataid", card), E.e("cardno", "1"), E.e("name", "TEST")], method: "sv6_new"))
Smoke.check("sv6_new 200", st == 200)

{st, doc} = Smoke.post_kbin("/local2/KFC:J:A:A:2020090402/game/sv6_load", "KFC:J:A:A:2020090402", E.e("game", [E.e("dataid", card)], method: "sv6_load"))
Smoke.check("sv6_load 200", st == 200 and XNode.child(doc, "game") != nil)

# sdvx via slashless forwarder
body = Kbinxml.encode(E.e("call", E.e("game", [E.e("dataid", card)], method: "sv6_load"), model: "KFC:J:A:A:2020090402", srcid: "A00000000000"))
{:ok, {{_, st, _}, _, resp}} = :httpc.request(:post, {~c"http://127.0.0.1:8000/fwdr?model=KFC:J:A:A:2020090402&f=game.sv6_load", [], ~c"application/octet-stream", body}, [], body_format: :binary)
Smoke.check("fwdr sv6_load 200", st == 200 and Kbinxml.is_binary_xml(resp))

# --- DDR
IO.puts("ddr")
{st, doc} = Smoke.post_kbin("/local2/MDX:J:A:A:2019022600/system/convcardnumber", "MDX:J:A:A:2019022600", E.e("system", [E.e("data", E.e("card_id", card))], method: "convcardnumber"))
Smoke.check("ddr convcardnumber 200", st == 200)

{st, doc} = Smoke.post_kbin("/local2/MDX:J:A:A:2019022600/playerdata/usergamedata_recv", "MDX:J:A:A:2019022600", E.e("playerdata", method: "usergamedata_recv", refid: card))
Smoke.check("ddr usergamedata_recv", st in [200, 500])  # 500 acceptable for unknown card (crash parity)

# --- GITADORA (versioned module names)
IO.puts("gitadora")
{st, doc} = Smoke.post_kbin("/local/M32:J:A:A:2024031300/gf10_shopinfo/regist", "M32:J:A:A:2024031300", E.e("gf10_shopinfo", method: "regist"))
Smoke.check("gf10_shopinfo regist 200", st == 200)

# gitadora via slashless forwarder (M32 special case)
body = Kbinxml.encode(E.e("call", E.e("gf10_shopinfo", method: "regist"), model: "M32:J:A:A:2024031300", srcid: "A00000000000"))
{:ok, {{_, st, _}, _, resp}} = :httpc.request(:post, {~c"http://127.0.0.1:8000/fwdr?model=M32:J:A:A:2024031300&f=gf10_shopinfo.regist", [], ~c"application/octet-stream", body}, [], body_format: :binary)
Smoke.check("fwdr gf10_shopinfo 200", st == 200 and Kbinxml.is_binary_xml(resp))

# --- DANCERUSH
IO.puts("drs")
{st, doc} = Smoke.post_kbin("/local/REC:J:A:A:2019022600/game/get_common", "REC:J:A:A:2019022600", E.e("game", method: "get_common"))
Smoke.check("drs get_common 200", st == 200)

# --- NOSTALGIA
IO.puts("nostalgia")
{st, doc} = Smoke.post_kbin("/local/PAN:J:A:A:2019022600/op3_common/get_common_info", "PAN:J:A:A:2019022600", E.e("op3_common", method: "get_common_info"))
Smoke.check("nostalgia get_common_info 200", st == 200)

# --- JSON APIs
IO.puts("json apis")
{st, profiles} = Smoke.get_json("/iidx/profiles")
Smoke.check("iidx profiles 200", st == 200 and is_list(profiles))

{st, _} = Smoke.get_json("/ddr/profiles")
Smoke.check("ddr profiles 200", st == 200)

{st, _} = Smoke.get_json("/gfdm/profiles")
Smoke.check("gfdm profiles 200", st == 200)

{st, _} = Smoke.get_json("/iidx/card/#{card}")
Smoke.check("iidx card lookup", st in [200, 406])

failures = Process.get(:failures, 0)
IO.puts("")
IO.puts(if failures == 0, do: "ALL CHECKS PASSED", else: "#{failures} CHECK(S) FAILED")
System.halt(if failures == 0, do: 0, else: 1)
