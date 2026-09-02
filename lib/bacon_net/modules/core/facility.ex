defmodule BaconNet.Modules.Core.Facility do
  @moduledoc "Port of modules/core/facility.py."

  alias BaconNet.{Config, Core, DB, E, XNode}

  def routes do
    %{
      prefix: "/core",
      tag: "facility",
      handlers: [{"facility", "get", :facility_get}]
    }
  end

  def facility_get(conn) do
    {info, conn} = Core.process_request(conn)
    pcbid = XNode.attr(info.root, "srcid")

    op = DB.get("shop", %{"pcbid" => pcbid}) || %{}
    opname = Map.get(op, "opname", Config.arcade())
    client_host = conn.remote_ip |> :inet.ntoa() |> to_string()

    response =
      E.e(
        "response",
        E.e(
          "facility",
          [
            E.e("location", [
              E.e("id", "EA000001", __type: "str"),
              E.e("country", "JP", __type: "str"),
              E.e("region", "JP-13", __type: "str"),
              E.e("customercode", "X000000001", __type: "str"),
              E.e("companycode", "X000000001", __type: "str"),
              E.e("latitude", 0, __type: "s32"),
              E.e("longitude", 0, __type: "s32"),
              E.e("accuracy", 0, __type: "u8"),
              E.e("countryname", "Japan", __type: "str"),
              E.e("regionname", "Tokyo", __type: "str"),
              E.e("countryjname", "日本国", __type: "str"),
              E.e("regionjname", "東京都", __type: "str"),
              E.e("name", opname, __type: "str"),
              E.e("type", 255, __type: "u8")
            ]),
            E.e("line", [
              E.e("class", 8, __type: "u8"),
              E.e("rtt", 500, __type: "u16"),
              E.e("upclass", 8, __type: "u8"),
              E.e("id", 3, __type: "str")
            ]),
            E.e("portfw", [
              E.e("globalip", client_host, __type: "ip4"),
              E.e("globalport", 5700, __type: "u16"),
              E.e("privateport", 5700, __type: "u16")
            ]),
            E.e("public", [
              E.e("flag", 1, __type: "u8"),
              E.e("name", opname, __type: "str"),
              E.e("latitude", 0, __type: "str"),
              E.e("longitude", 0, __type: "str")
            ]),
            E.e("share", [
              E.e("eacoin", [
                E.e("notchamount", 3000, __type: "s32"),
                E.e("notchcount", 3, __type: "s32"),
                E.e("supplylimit", 9999, __type: "s32")
              ]),
              E.e("eapass", E.e("valid", 365, __type: "u16")),
              E.e("url", [
                E.e("eapass", "www.ea-pass.konami.net", __type: "str"),
                E.e("arcadefan", "www.konami.jp/am", __type: "str"),
                E.e("konaminetdx", "http://am.573.jp", __type: "str"),
                E.e("konamiid", "https://id.konami.net", __type: "str"),
                E.e("eagate", "http://eagate.573.jp", __type: "str")
              ])
            ])
          ],
          expire: 10800
        )
      )

    Core.send_response(conn, info, response)
  end
end
