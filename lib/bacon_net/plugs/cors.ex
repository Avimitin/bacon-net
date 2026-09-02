defmodule BaconNet.Plugs.CORS do
  @moduledoc """
  Permissive CORS headers (FastAPI CORSMiddleware counterpart).
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn =
      conn
      |> put_resp_header("access-control-allow-origin", "*")
      |> put_resp_header("access-control-allow-credentials", "true")
      |> put_resp_header("access-control-allow-methods", "*")
      |> put_resp_header("access-control-allow-headers", "*")

    if conn.method == "OPTIONS" do
      conn |> send_resp(204, "") |> halt()
    else
      conn
    end
  end
end
