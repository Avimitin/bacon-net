defmodule BaconNet.Modules.Core.Apsmanager do
  @moduledoc false

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/core",
      tag: "apsmanager",
      handlers: [{"apsmanager", "getstat", :apsmanager_getstat}]
    }
  end

  def apsmanager_getstat(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("apsmanager", expire: 600)))
  end
end
