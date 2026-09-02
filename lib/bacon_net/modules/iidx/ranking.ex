defmodule BaconNet.Modules.Iidx.Ranking do
  @moduledoc "Port of modules/iidx/ranking.py."

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"ranking", "getranker", :ranking_getranker}
      ]
    }
  end

  def ranking_getranker(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("ranking")))
  end
end
