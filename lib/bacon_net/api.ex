defmodule BaconNet.Api do
  @moduledoc "Helpers for JSON API handlers (modules/*/api.py counterparts)."

  import Plug.Conn

  alias BaconNet.Config

  @doc "Send a JSON response."
  def json(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(data))
  end

  @doc "Send a JSON error response with the given status."
  def error(conn, status, reason) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{"error" => reason}))
  end

  @doc """
  Check the admin gate (used by /manage). When `Config.admin_token()` is unset
  the API is open (development default); otherwise the request must carry
  `Authorization: Bearer <token>`. Returns :ok or :unauthorized.
  """
  def authorize_admin(conn) do
    case Config.admin_token() do
      nil ->
        :ok

      token ->
        case get_req_header(conn, "authorization") do
          ["Bearer " <> given] ->
            if Plug.Crypto.secure_compare(given, token), do: :ok, else: :unauthorized

          _ ->
            :unauthorized
        end
    end
  end

  @doc """
  Display name of a profile document: the name from the highest numeric entry
  of its per-version map. Games name it differently ("name", "djname").
  """
  def profile_name(%{"version" => versions}) when is_map(versions) do
    versions
    |> Enum.filter(fn {k, v} -> is_binary(k) and is_map(v) end)
    |> Enum.sort_by(fn {k, _} ->
      case Integer.parse(k) do
        {n, _} -> n
        :error -> 0
      end
    end)
    |> List.last()
    |> then(fn
      nil -> nil
      {_version, data} -> data["name"] || data["djname"]
    end)
  end

  def profile_name(_), do: nil
end
