defmodule BaconNet.Modules.Iidx.Iidx29lobby do
  @moduledoc false

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local2",
      tag: "local2",
      handlers: [
        {"IIDX29lobby", "entry", :iidx29lobby_entry},
        {"IIDX29lobby", "update", :iidx29lobby_update},
        {"IIDX29lobby", "delete", :iidx29lobby_delete},
        {"IIDX29lobby", "bplbattle_entry", :iidx29lobby_bplbattle_entry},
        {"IIDX29lobby", "bplbattle_update", :iidx29lobby_bplbattle_update},
        {"IIDX29lobby", "bplbattle_delete", :iidx29lobby_bplbattle_delete}
      ]
    }
  end

  def iidx29lobby_entry(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("IIDX29lobby")))
  end

  def iidx29lobby_update(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("IIDX29lobby")))
  end

  def iidx29lobby_delete(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("IIDX29lobby")))
  end

  def iidx29lobby_bplbattle_entry(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("IIDX29lobby")))
  end

  def iidx29lobby_bplbattle_update(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("IIDX29lobby")))
  end

  def iidx29lobby_bplbattle_delete(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("IIDX29lobby")))
  end
end
