defmodule BaconNet.Plugs.SecurityHeaders do
  @moduledoc """
  Browser security headers. CSP matters for the webui; the rest is cheap
  defense in depth. Game protocol clients ignore unknown headers.
  """

  @behaviour Plug

  import Plug.Conn

  @csp [
    "default-src 'self'",
    "img-src 'self' data:",
    "style-src 'self' 'unsafe-inline'",
    "script-src 'self'",
    "connect-src 'self'",
    "frame-ancestors 'none'",
    "base-uri 'self'"
  ]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn
    |> put_resp_header("content-security-policy", Enum.join(@csp, "; "))
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("referrer-policy", "no-referrer")
  end
end
