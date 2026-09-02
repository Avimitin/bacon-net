defmodule BaconNet.Modules.Iidx.Iidx33streaming do
  @moduledoc "Port of modules/iidx/iidx33streaming.py."

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"IIDX33streaming", "common", :iidx33streaming_common},
        {"IIDX33streaming", "getcm", :iidx33streaming_getcm}
      ]
    }
  end

  def iidx33streaming_common(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX33streaming")))
  end

  def iidx33streaming_getcm(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX33streaming")))
  end
end
