defmodule BaconNet.Modules.Iidx.Iidx29shop do
  @moduledoc "Port of modules/iidx/iidx29shop.py."

  alias BaconNet.{Config, Core, E}

  def routes do
    %{
      prefix: "/local2",
      tag: "local2",
      handlers: [
        {"IIDX29shop", "getname", :iidx29shop_getname},
        {"IIDX29shop", "getconvention", :iidx29shop_getconvention},
        {"IIDX29shop", "sentinfo", :iidx29shop_sentinfo},
        {"IIDX29shop", "sendescapepackageinfo", :iidx29shop_sendescapepackageinfo}
      ]
    }
  end

  def iidx29shop_getname(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e("response",
        E.e("IIDX29shop",
          cls_opt: 0,
          opname: Config.arcade(),
          pid: 13
        )
      )

    Core.send_response(conn, info, response)
  end

  def iidx29shop_getconvention(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e("response",
        E.e("IIDX29shop", E.e("valid", 1, __type: "bool"),
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

  def iidx29shop_sentinfo(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX29shop")))
  end

  def iidx29shop_sendescapepackageinfo(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX29shop", expire: 1200)))
  end
end
