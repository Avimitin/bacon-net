defmodule BaconNet.Modules.Core.Package do
  @moduledoc "Port of modules/core/package.py."

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/core",
      tag: "package",
      handlers: [
        {"package", "list", :package_list},
        {"package", "intend", :package_intend}
      ]
    }
  end

  def package_list(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("package", expire: 1200, status: 0)))
  end

  def package_intend(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("package", status: 0)))
  end
end
