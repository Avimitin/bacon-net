defmodule BaconNet.Modules.Gitadora.Shopinfo do
  @moduledoc "Port of modules/gitadora/shopinfo.py."

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"{ver}_shopinfo", "regist", :gitadora_shopinfo_regist}
      ]
    }
  end

  def gitadora_shopinfo_regist(conn, ver) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("#{ver}_shopinfo", [
          E.e("data", [
            E.e("cabid", 1, __type: "u32"),
            E.e("locationid", "EA000001", __type: "str"),
            E.e("is_send", 0, __type: "u8")
          ]),
          E.e(
            "temperature",
            E.e("is_send", 0, __type: "bool")
          ),
          E.e(
            "tax",
            E.e("tax_phase", 1, __type: "s32")
          )
        ])
      )

    Core.send_response(conn, info, response)
  end
end
