defmodule BaconNet.Modules.Iidx.Iidx33shop do
  @moduledoc "Port of modules/iidx/iidx33shop.py."

  alias BaconNet.{Config, Core, E, Shop, XNode}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"IIDX33shop", "getname", :iidx33shop_getname},
        {"IIDX33shop", "savename", :iidx33shop_savename},
        {"IIDX33shop", "getconvention", :iidx33shop_getconvention},
        {"IIDX33shop", "sentinfo", :iidx33shop_sentinfo},
        {"IIDX33shop", "sendescapepackageinfo", :iidx33shop_sendescapepackageinfo},
        {"IIDX33shop", "getclosingtime", :iidx33shop_getclosingtime},
        {"IIDX33shop", "saveclosingtime", :iidx33shop_saveclosingtime}
      ]
    }
  end

  def iidx33shop_getname(conn) do
    {info, conn} = Core.process_request(conn)
    pcbid = XNode.attr(info.root, "srcid")

    opname = Shop.opname_for(pcbid) || Config.arcade()

    response =
      E.e(
        "response",
        E.e("IIDX33shop",
          cls_opt: 0,
          opname: opname,
          pid: 13
        )
      )

    Core.send_response(conn, info, response)
  end

  def iidx33shop_savename(conn) do
    {info, conn} = Core.process_request(conn)
    pcbid = XNode.attr(info.root, "srcid")
    opname = Core.module_node(info) |> XNode.attr("opname")

    # The cabinet is guaranteed permitted by the guard; permit is idempotent
    # there and updates the display label.
    Shop.permit(pcbid, opname)

    Core.send_response(conn, info, E.e("response", E.e("IIDX33shop")))
  end

  def iidx33shop_getconvention(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("IIDX33shop", E.e("valid", 1, __type: "bool"),
          music_0: -1,
          music_1: -1,
          music_2: -1,
          music_3: -1,
          start_time: 0,
          end_time: 0
        )
      )

    Core.send_response(conn, info, response)
  end

  def iidx33shop_sentinfo(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX33shop")))
  end

  def iidx33shop_sendescapepackageinfo(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX33shop", expire: 1200)))
  end

  def iidx33shop_getclosingtime(conn) do
    {info, conn} = Core.process_request(conn)

    weeks = for i <- 0..6, do: E.e("week", cls_opt: 0, week: i)

    response =
      E.e("response", E.e("IIDX33shop", [E.e("exist", 1, __type: "bool")] ++ weeks))

    Core.send_response(conn, info, response)
  end

  def iidx33shop_saveclosingtime(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX33shop")))
  end
end
