defmodule BaconNet.Modules.Core.Message do
  @moduledoc false

  alias BaconNet.{Config, Core, E}

  def routes do
    %{
      prefix: "/core",
      tag: "message",
      handlers: [{"message", "get", :message_get}]
    }
  end

  def message_get(conn) do
    {info, conn} = Core.process_request(conn)

    items =
      if Config.maintenance_mode() do
        for s <- ["sys.mainte", "sys.eacoin.mainte"] do
          E.e("item", name: s, start: 0, end: 604_800)
        end
      else
        []
      end

    Core.send_response(conn, info, E.e("response", E.e("message", items, expire: 300)))
  end
end
