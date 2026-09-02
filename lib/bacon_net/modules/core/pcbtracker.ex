defmodule BaconNet.Modules.Core.Pcbtracker do
  @moduledoc "Port of modules/core/pcbtracker.py."

  alias BaconNet.{Config, Core, E}

  def routes do
    %{
      prefix: "/core",
      tag: "pcbtracker",
      handlers: [{"pcbtracker", "alive", :pcbtracker_alive}]
    }
  end

  def pcbtracker_alive(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("pcbtracker",
          status: 0,
          expire: 1200,
          ecenable: not Config.maintenance_mode(),
          eclimit: 0,
          limit: 0,
          time: :os.system_time(:second)
        )
      )

    Core.send_response(conn, info, response)
  end
end
