defmodule BaconNet.Modules.Iidx.Iidx29ranking do
  @moduledoc "Port of modules/iidx/iidx29ranking.py."

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local2",
      tag: "local2",
      handlers: [
        {"IIDX29ranking", "getranker", :iidx29ranking_getranker}
      ]
    }
  end

  def iidx29ranking_getranker(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX29ranking")))
  end
end
