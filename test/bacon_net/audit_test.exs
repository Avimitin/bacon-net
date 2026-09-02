defmodule BaconNet.AuditTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias BaconNet.{Audit, Repo, Tenancy}

  @token "audit-test-token"

  setup do
    Application.put_env(:bacon_net, :admin_token, @token)
    Repo.delete_all(Audit.Event)

    on_exit(fn ->
      Application.delete_env(:bacon_net, :admin_token)
      Repo.delete_all(Audit.Event)
      Tenancy.delete("AUDITSHOPPCBID01")
    end)

    :ok
  end

  defp call(method, path, body \\ nil, token \\ @token) do
    conn =
      if body do
        conn(method, path, Jason.encode!(body))
        |> Plug.Conn.put_req_header("content-type", "application/json")
      else
        conn(method, path)
      end

    conn =
      if token, do: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}"), else: conn

    BaconNet.Router.call(conn, BaconNet.Router.init([]))
  end

  defp json(conn), do: Jason.decode!(conn.resp_body)

  test "admin mutations write audit events" do
    conn = call(:post, "/manage/api/shops", %{"pcbid" => "AUDITSHOPPCBID01"})
    assert conn.status == 201

    {events, _} = Audit.list()
    assert [event] = Enum.filter(events, &(&1.action == "shop.add"))
    assert event.actor == "admin"
    assert event.target == "AUDITSHOPPCBID01"
    assert event.outcome == "ok"
    assert is_binary(event.request_id)

    conn = call(:post, "/manage/api/shops/AUDITSHOPPCBID01/revoke")
    assert conn.status == 200

    {events, _} = Audit.list()
    assert [%{action: "shop.revoke", target: "AUDITSHOPPCBID01"} | _] = events
  end

  test "audit endpoint requires the admin token" do
    assert call(:get, "/manage/api/audit", nil, nil).status == 401
    assert call(:get, "/manage/api/audit", nil, "wrong").status == 401

    # closed entirely when no token configured
    Application.delete_env(:bacon_net, :admin_token)
    assert call(:get, "/manage/api/audit").status == 401
  end

  test "audit endpoint lists newest first and paginates by cursor" do
    for i <- 1..5 do
      {:ok, _} =
        Audit.record(%{actor: "admin", action: "test.event", target: "t#{i}", outcome: "ok"})
    end

    conn = call(:get, "/manage/api/audit?limit=2")
    assert conn.status == 200
    %{"events" => page1, "next_cursor" => cursor} = json(conn)
    assert length(page1) == 2
    assert is_integer(cursor)
    assert page1 |> Enum.map(& &1["target"]) == ["t5", "t4"]

    conn = call(:get, "/manage/api/audit?limit=2&cursor=#{cursor}")
    %{"events" => page2, "next_cursor" => cursor2} = json(conn)
    assert page2 |> Enum.map(& &1["target"]) == ["t3", "t2"]

    conn = call(:get, "/manage/api/audit?limit=2&cursor=#{cursor2}")
    %{"events" => page3, "next_cursor" => nil} = json(conn)
    assert page3 |> Enum.map(& &1["target"]) == ["t1"]
  end

  test "audit endpoint clamps the limit" do
    for i <- 1..3 do
      {:ok, _} =
        Audit.record(%{actor: "admin", action: "test.clamp", target: "c#{i}", outcome: "ok"})
    end

    conn = call(:get, "/manage/api/audit?limit=99999")
    assert conn.status == 200
    %{"events" => events} = json(conn)
    assert length(events) == 3

    # garbage limit falls back to the default
    conn = call(:get, "/manage/api/audit?limit=abc")
    assert conn.status == 200
  end
end
