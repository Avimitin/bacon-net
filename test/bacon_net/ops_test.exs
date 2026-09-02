defmodule BaconNet.OpsTest do
  use ExUnit.Case, async: false

  import Plug.Test

  @token "ops-test-token"

  setup do
    Application.put_env(:bacon_net, :admin_token, @token)
    on_exit(fn -> Application.delete_env(:bacon_net, :admin_token) end)
    :ok
  end

  defp call(method, path, headers \\ []) do
    conn = conn(method, path)

    headers
    |> Enum.reduce(conn, fn {k, v}, c -> Plug.Conn.put_req_header(c, k, v) end)
    |> BaconNet.Router.call(BaconNet.Router.init([]))
  end

  defp resp_header(conn, name) do
    conn.resp_headers |> Enum.find_value(fn {k, v} -> if k == name, do: v end)
  end

  test "healthz is always 200 without auth" do
    conn = call(:get, "/healthz")
    assert conn.status == 200
    assert conn.resp_body =~ "ok"
  end

  test "readyz is 200 when the repo answers" do
    conn = call(:get, "/readyz")
    assert conn.status == 200
  end

  test "readyz is 503 when the readiness check fails" do
    Application.put_env(:bacon_net, :readiness_check, fn -> {:error, :down} end)

    try do
      conn = call(:get, "/readyz")
      assert conn.status == 503
    after
      Application.delete_env(:bacon_net, :readiness_check)
    end
  end

  test "readyz is 503 when the readiness check raises" do
    Application.put_env(:bacon_net, :readiness_check, fn -> raise "db gone" end)

    try do
      conn = call(:get, "/readyz")
      assert conn.status == 503
    after
      Application.delete_env(:bacon_net, :readiness_check)
    end
  end

  test "metrics requires the admin token" do
    assert call(:get, "/metrics").status == 401
    assert call(:get, "/metrics", [{"authorization", "Bearer wrong"}]).status == 401
  end

  test "metrics renders Prometheus text with http and repo counters" do
    call(:get, "/healthz")

    conn = call(:get, "/metrics", [{"authorization", "Bearer #{@token}"}])
    assert conn.status == 200
    assert resp_header(conn, "content-type") =~ "text/plain"

    body = conn.resp_body
    assert body =~ ~s(bacon_net_http_requests_total{route_class="healthz",status="200"})
    assert body =~ "bacon_net_repo_queries_total"
  end

  test "request id is generated and echoed back" do
    conn = call(:get, "/healthz")
    id = resp_header(conn, "x-request-id")
    assert is_binary(id)
    assert byte_size(id) == 24
  end

  test "a valid incoming x-request-id is honored" do
    conn = call(:get, "/healthz", [{"x-request-id", "req_ABC-123.x"}])
    assert resp_header(conn, "x-request-id") == "req_ABC-123.x"
  end

  test "an oversized or unsafe x-request-id is replaced" do
    conn = call(:get, "/healthz", [{"x-request-id", String.duplicate("a", 100)}])
    assert resp_header(conn, "x-request-id") != String.duplicate("a", 100)

    conn = call(:get, "/healthz", [{"x-request-id", "bad id<script>"}])
    assert resp_header(conn, "x-request-id") =~ ~r/^[A-Za-z0-9._-]+$/
  end
end
