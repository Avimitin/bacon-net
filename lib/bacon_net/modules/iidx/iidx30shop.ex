defmodule BaconNet.Modules.Iidx.Iidx30shop do
  @moduledoc "Port of modules/iidx/iidx30shop.py."

  alias BaconNet.{Config, Core, E}

  def routes do
    %{
      prefix: "/local2",
      tag: "local2",
      handlers: [
        {"IIDX30shop", "getname", :iidx30shop_getname},
        {"IIDX30shop", "getconvention", :iidx30shop_getconvention},
        {"IIDX30shop", "sentinfo", :iidx30shop_sentinfo},
        {"IIDX30shop", "sendescapepackageinfo", :iidx30shop_sendescapepackageinfo}
      ]
    }
  end

  def iidx30shop_getname(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("IIDX30shop",
          cls_opt: 0,
          opname: Config.arcade(),
          pid: 13
        )
      )

    Core.send_response(conn, info, response)
  end

  def iidx30shop_getconvention(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("IIDX30shop", E.e("valid", 1, __type: "bool"),
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

  def iidx30shop_sentinfo(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX30shop")))
  end

  def iidx30shop_sendescapepackageinfo(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX30shop", expire: 1200)))
  end
end
