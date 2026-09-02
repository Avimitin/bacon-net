defmodule BaconNet.Modules.Core.Package2 do
  @moduledoc "Port of modules/core/package2.py."

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/core",
      tag: "package2",
      handlers: [{"package2", "list", :package2_list}]
    }
  end

  def package2_list(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("package2", expire: 1200, status: 0)))
  end
end
