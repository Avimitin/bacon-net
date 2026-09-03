defmodule BaconNet.Modules.Iidx.Iidx31ranking do
  @moduledoc false

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local2",
      tag: "local2",
      handlers: [
        {"IIDX31ranking", "getranker", :iidx31ranking_getranker}
      ]
    }
  end

  def iidx31ranking_getranker(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX31ranking")))
  end
end
