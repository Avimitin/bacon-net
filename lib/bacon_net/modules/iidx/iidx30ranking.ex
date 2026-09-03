defmodule BaconNet.Modules.Iidx.Iidx30ranking do
  @moduledoc false

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local2",
      tag: "local2",
      handlers: [
        {"IIDX30ranking", "getranker", :iidx30ranking_getranker}
      ]
    }
  end

  def iidx30ranking_getranker(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX30ranking")))
  end
end
