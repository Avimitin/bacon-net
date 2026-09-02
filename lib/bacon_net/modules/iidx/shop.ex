defmodule BaconNet.Modules.Iidx.Shop do
  @moduledoc "Port of modules/iidx/shop.py."

  alias BaconNet.{Config, Core, E}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"shop", "getname", :shop_getname},
        {"shop", "getconvention", :shop_getconvention},
        {"shop", "sentinfo", :shop_sentinfo},
        {"shop", "sendescapepackageinfo", :shop_sendescapepackageinfo}
      ]
    }
  end

  def shop_getname(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("shop",
          cls_opt: 0,
          opname: Config.arcade(),
          pid: 13
        )
      )

    Core.send_response(conn, info, response)
  end

  def shop_getconvention(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("shop", E.e("valid", 1, __type: "bool"),
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

  def shop_sentinfo(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("shop")))
  end

  def shop_sendescapepackageinfo(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("shop", expire: 1200)))
  end
end
