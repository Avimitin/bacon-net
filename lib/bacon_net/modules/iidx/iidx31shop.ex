defmodule BaconNet.Modules.Iidx.Iidx31shop do
  @moduledoc "Port of modules/iidx/iidx31shop.py."

  alias BaconNet.{Config, Core, E}

  def routes do
    %{
      prefix: "/local2",
      tag: "local2",
      handlers: [
        {"IIDX31shop", "getname", :iidx31shop_getname},
        {"IIDX31shop", "getconvention", :iidx31shop_getconvention},
        {"IIDX31shop", "sentinfo", :iidx31shop_sentinfo},
        {"IIDX31shop", "sendescapepackageinfo", :iidx31shop_sendescapepackageinfo}
      ]
    }
  end

  def iidx31shop_getname(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e("response",
        E.e("IIDX31shop",
          cls_opt: 0,
          opname: Config.arcade(),
          pid: 13
        )
      )

    Core.send_response(conn, info, response)
  end

  def iidx31shop_getconvention(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e("response",
        E.e("IIDX31shop", E.e("valid", 1, __type: "bool"),
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

  def iidx31shop_sentinfo(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX31shop")))
  end

  def iidx31shop_sendescapepackageinfo(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX31shop", expire: 1200)))
  end
end
