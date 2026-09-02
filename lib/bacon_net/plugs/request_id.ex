defmodule BaconNet.Plugs.RequestId do
  @moduledoc """
  Request id plug: honors an incoming `x-request-id` header when it is
  short and charset-safe (<= 64 chars of [A-Za-z0-9._-]), otherwise generates
  a fresh id. The id lands in Logger metadata, `conn.assigns[:request_id]`
  (picked up by audit events and the request context), and the
  `x-request-id` response header.
  """

  require Logger

  import Plug.Conn

  @behaviour Plug

  @max_len 64
  @valid_re ~r/^[A-Za-z0-9._-]+$/

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    request_id = incoming(conn) || generate()

    Logger.metadata(request_id: request_id)

    conn
    |> assign(:request_id, request_id)
    |> put_resp_header("x-request-id", request_id)
  end

  defp incoming(conn) do
    case get_req_header(conn, "x-request-id") do
      [id | _] when byte_size(id) <= @max_len ->
        if id =~ @valid_re, do: id, else: nil

      _ ->
        nil
    end
  end

  defp generate do
    :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
  end
end
