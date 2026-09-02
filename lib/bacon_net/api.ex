defmodule BaconNet.Api do
  @moduledoc "Helpers for JSON API handlers (modules/*/api.py counterparts)."

  import Plug.Conn

  @doc "Send a JSON response."
  def json(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(data))
  end
end
