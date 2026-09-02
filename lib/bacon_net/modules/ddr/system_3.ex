defmodule BaconNet.Modules.Ddr.System3 do
  @moduledoc "Port of modules/ddr/system_3.py."

  alias BaconNet.{Card, Core, E, XNode}

  def routes do
    %{
      prefix: "/local2",
      tag: "local2",
      handlers: [{"system_3", "convcardnumber", :system_3_convcardnumber}]
    }
  end

  def system_3_convcardnumber(conn) do
    {info, conn} = Core.process_request(conn)
    cid = Core.module_node(info) |> XNode.child("data") |> XNode.child("card_id") |> Map.get(:text)

    response =
      E.e("response",
        E.e("system_3", [
          E.e("data", E.e("card_number", Card.to_konami_id(cid), __type: "str")),
          E.e("result", 0, __type: "s32")
        ])
      )

    Core.send_response(conn, info, response)
  end
end
