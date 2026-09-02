defmodule BaconNet.Modules.Iidx.Iidx32shop do
  @moduledoc "Port of modules/iidx/iidx32shop.py."

  alias BaconNet.{Config, Core, E}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"IIDX32shop", "getname", :iidx32shop_getname},
        {"IIDX32shop", "getconvention", :iidx32shop_getconvention},
        {"IIDX32shop", "sentinfo", :iidx32shop_sentinfo},
        {"IIDX32shop", "sendescapepackageinfo", :iidx32shop_sendescapepackageinfo}
      ]
    }
  end

  def iidx32shop_getname(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("IIDX32shop",
          cls_opt: 0,
          opname: Config.arcade(),
          pid: 13
        )
      )

    Core.send_response(conn, info, response)
  end

  def iidx32shop_getconvention(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("IIDX32shop", E.e("valid", 1, __type: "bool"),
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

  def iidx32shop_sentinfo(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX32shop")))
  end

  def iidx32shop_sendescapepackageinfo(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX32shop", expire: 1200)))
  end
end
