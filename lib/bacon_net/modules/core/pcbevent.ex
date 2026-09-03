defmodule BaconNet.Modules.Core.Pcbevent do
  @moduledoc false

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/core",
      tag: "pcbevent",
      handlers: [{"pcbevent", "put", :pcbevent_put}]
    }
  end

  def pcbevent_put(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("pcbevent", expire: 600)))
  end
end
