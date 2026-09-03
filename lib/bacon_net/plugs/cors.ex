defmodule BaconNet.Plugs.CORS do
  @moduledoc """
  CORS headers for allowlisted origins.

  Only request origins listed in `config :bacon_net, cors_origins` (default
  `[]`) receive CORS headers; the allowlist is reflected origin-for-origin and
  never `*`, so it can safely combine with credentials. Same-origin requests
  carry no Origin header and pass through untouched.
  """

  import Plug.Conn

  alias BaconNet.Config

  def init(opts), do: opts

  def call(conn, _opts) do
    origin = get_req_header(conn, "origin") |> List.first()

    conn =
      if origin && origin in Config.cors_origins() do
        conn
        |> put_resp_header("access-control-allow-origin", origin)
        |> put_resp_header("access-control-allow-credentials", "true")
        |> put_resp_header(
          "access-control-allow-methods",
          "GET, POST, PUT, PATCH, DELETE, OPTIONS"
        )
        |> put_resp_header(
          "access-control-allow-headers",
          "authorization, content-type, x-csrf-requested-with"
        )
        |> put_resp_header("vary", "origin")
      else
        conn
      end

    if conn.method == "OPTIONS" and origin do
      conn |> send_resp(204, "") |> halt()
    else
      conn
    end
  end
end
