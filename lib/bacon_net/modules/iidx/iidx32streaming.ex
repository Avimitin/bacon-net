defmodule BaconNet.Modules.Iidx.Iidx32streaming do
  @moduledoc false

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"IIDX32streaming", "common", :iidx32streaming_common},
        {"IIDX32streaming", "getcm", :iidx32streaming_getcm}
      ]
    }
  end

  def iidx32streaming_common(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX32streaming")))
  end

  def iidx32streaming_getcm(conn) do
    {info, conn} = Core.process_request(conn)

    Core.send_response(conn, info, E.e("response", E.e("IIDX32streaming")))
  end
end
