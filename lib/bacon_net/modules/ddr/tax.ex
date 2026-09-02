defmodule BaconNet.Modules.Ddr.Tax do
  @moduledoc "Port of modules/ddr/tax.py."

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [{"tax", "get_phase", :tax_get_phase}]
    }
  end

  def tax_get_phase(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e("response",
        E.e("tax", E.e("phase", 0, __type: "s32"))
      )

    Core.send_response(conn, info, response)
  end
end
