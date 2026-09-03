defmodule BaconNet.Modules.Core.Dlstatus do
  @moduledoc false

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/core",
      tag: "dlstatus",
      handlers: [
        {"dlstatus", "done", :dlstatus_done},
        {"dlstatus", "progress", :dlstatus_progress}
      ]
    }
  end

  def dlstatus_done(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("dlstatus", status: 0)))
  end

  def dlstatus_progress(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("dlstatus", status: 0)))
  end
end
