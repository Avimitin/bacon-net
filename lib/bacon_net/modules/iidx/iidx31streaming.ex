defmodule BaconNet.Modules.Iidx.Iidx31streaming do
  @moduledoc "Port of modules/iidx/iidx31streaming.py."

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local2",
      tag: "local2",
      handlers: [
        {"IIDX31streaming", "common", :iidx31streaming_common},
        {"IIDX31streaming", "getcm", :iidx31streaming_getcm}
      ]
    }
  end

  def iidx31streaming_common(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX31streaming")))
  end

  def iidx31streaming_getcm(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX31streaming")))
  end
end
