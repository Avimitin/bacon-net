defmodule BaconNet.Modules.Ddr.Wordcheck3 do
  @moduledoc false

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local2",
      tag: "local2",
      handlers: [{"wordcheck_3", "tabooword_check", :wordcheck_3_tabooword_check}]
    }
  end

  def wordcheck_3_tabooword_check(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("wordcheck_3", [
          E.e("result", 0, __type: "s32"),
          E.e("is_taboo", 0, __type: "bool")
        ])
      )

    Core.send_response(conn, info, response)
  end
end
