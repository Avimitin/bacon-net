defmodule BaconNet.Modules.Core.Ins do
  @moduledoc false

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/core",
      tag: "ins",
      handlers: [
        {"ins", "netlog", :ins_netlog},
        {"ins", "send", :ins_send}
      ]
    }
  end

  def ins_netlog(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("netlog", status: 0)))
  end

  def ins_send(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("netlog", status: 0)))
  end
end
