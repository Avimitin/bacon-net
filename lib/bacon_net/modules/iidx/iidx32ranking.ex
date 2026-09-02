defmodule BaconNet.Modules.Iidx.Iidx32ranking do
  @moduledoc "Port of modules/iidx/iidx32ranking.py."

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"IIDX32ranking", "getranker", :iidx32ranking_getranker}
      ]
    }
  end

  def iidx32ranking_getranker(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX32ranking")))
  end
end
