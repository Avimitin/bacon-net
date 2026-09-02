defmodule BaconNet.Plugs.CORSTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  alias BaconNet.Plugs.CORS

  setup do
    old = Application.get_env(:bacon_net, :cors_origins)
    Application.put_env(:bacon_net, :cors_origins, ["https://allowed.example"])

    on_exit(fn ->
      if old,
        do: Application.put_env(:bacon_net, :cors_origins, old),
        else: Application.delete_env(:bacon_net, :cors_origins)
    end)

    :ok
  end

  defp call(conn), do: CORS.call(conn, CORS.init([]))

  test "allowlisted origin is reflected with credentials" do
    conn = call(conn(:get, "/config") |> put_req_header("origin", "https://allowed.example"))

    assert get_resp_header(conn, "access-control-allow-origin") == ["https://allowed.example"]
    assert get_resp_header(conn, "access-control-allow-credentials") == ["true"]
    refute conn.halted
  end

  test "non-allowlisted origin gets no CORS headers" do
    conn = call(conn(:get, "/config") |> put_req_header("origin", "https://evil.example"))

    assert get_resp_header(conn, "access-control-allow-origin") == []
    assert get_resp_header(conn, "access-control-allow-credentials") == []
    refute conn.halted
  end

  test "requests without an Origin header get no CORS headers" do
    conn = call(conn(:get, "/config"))

    assert get_resp_header(conn, "access-control-allow-origin") == []
    refute conn.halted
  end

  test "OPTIONS preflight from an allowlisted origin answers 204 with headers" do
    conn = call(conn(:options, "/config") |> put_req_header("origin", "https://allowed.example"))

    assert conn.status == 204
    assert conn.halted
    assert get_resp_header(conn, "access-control-allow-origin") == ["https://allowed.example"]
  end

  test "OPTIONS preflight from a non-allowlisted origin answers 204 without CORS headers" do
    conn = call(conn(:options, "/config") |> put_req_header("origin", "https://evil.example"))

    assert conn.status == 204
    assert conn.halted
    assert get_resp_header(conn, "access-control-allow-origin") == []
  end

  test "wildcard is never emitted, even if configured" do
    Application.put_env(:bacon_net, :cors_origins, ["*"])

    conn = call(conn(:get, "/config") |> put_req_header("origin", "https://anything.example"))
    assert get_resp_header(conn, "access-control-allow-origin") == []
    assert get_resp_header(conn, "access-control-allow-credentials") == []
  end
end
