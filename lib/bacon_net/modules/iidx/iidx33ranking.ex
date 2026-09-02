defmodule BaconNet.Modules.Iidx.Iidx33ranking do
  @moduledoc "Port of modules/iidx/iidx33ranking.py."

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"IIDX33ranking", "getranker", :iidx33ranking_getranker}
      ]
    }
  end

  def iidx33ranking_getranker(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX33ranking")))
  end
end
