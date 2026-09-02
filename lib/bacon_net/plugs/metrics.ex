defmodule BaconNet.Plugs.Metrics do
  @moduledoc """
  Emits the `[:bacon_net, :http, :request]` telemetry event for every
  request, with `duration` (native units) and metadata `route_class` (the
  first path segment) and `status`. Consumed by `BaconNet.Telemetry`.
  """

  import Plug.Conn

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    start = System.monotonic_time()

    register_before_send(conn, fn conn ->
      :telemetry.execute(
        [:bacon_net, :http, :request],
        %{count: 1, duration: System.monotonic_time() - start},
        %{route_class: route_class(conn), status: conn.status}
      )

      conn
    end)
  end

  defp route_class(conn) do
    case conn.path_info do
      [first | _] -> first
      [] -> "root"
    end
  end
end
