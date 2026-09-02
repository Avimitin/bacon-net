defmodule BaconNet.ManageTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias BaconNet.DB

  @table "test_manage"
  @token "manage-test-token"

  setup do
    DB.drop_table(@table)
    Application.put_env(:bacon_net, :admin_token, @token)

    on_exit(fn ->
      DB.drop_table(@table)
      Application.delete_env(:bacon_net, :admin_token)
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

  defp json(conn) do
    assert conn.resp_headers |> Enum.find(fn {k, _} -> k == "content-type" end) |> elem(1) =~
             "application/json"

    Jason.decode!(conn.resp_body)
  end

  test "tables lists tables with counts" do
    conn = call(:get, "/manage/api/tables")
    assert conn.status == 200
    assert %{"tables" => _} = json(conn)
  end

  test "admin API is closed when no token is configured" do
    Application.delete_env(:bacon_net, :admin_token)
    assert call(:get, "/manage/api/tables").status == 401
    assert call(:post, "/manage/api/shops", %{"pcbid" => "SHOPTESTPCBID02"}).status == 401
  end

  test "wrong or missing token is rejected" do
    assert call(:get, "/manage/api/tables", nil, "wrong-token").status == 401
    assert call(:get, "/manage/api/tables", nil, nil).status == 401
  end

  test "document CRUD roundtrip" do
    # insert
    conn = call(:post, "/manage/api/table/#{@table}", %{"name" => "alice", "score" => 10})
    assert conn.status == 201
    %{"_id" => id, "name" => "alice"} = json(conn)

    # list
    conn = call(:get, "/manage/api/table/#{@table}")
    assert %{"docs" => [%{"_id" => ^id, "name" => "alice"}]} = json(conn)

    # get
    conn = call(:get, "/manage/api/table/#{@table}/#{id}")
    assert conn.status == 200
    assert %{"score" => 10} = json(conn)

    # patch (merge)
    conn = call(:patch, "/manage/api/table/#{@table}/#{id}", %{"score" => 20})
    assert conn.status == 200
    assert %{"name" => "alice", "score" => 20} = json(conn)

    # put (replace)
    conn = call(:put, "/manage/api/table/#{@table}/#{id}", %{"name" => "bob"})
    assert conn.status == 200
    assert json(conn) == %{"_id" => id, "name" => "bob"}

    # delete
    conn = call(:delete, "/manage/api/table/#{@table}/#{id}")
    assert conn.status == 204

    conn = call(:get, "/manage/api/table/#{@table}/#{id}")
    assert conn.status == 404
  end

  test "missing document returns 404" do
    assert call(:get, "/manage/api/table/#{@table}/999").status == 404
    assert call(:patch, "/manage/api/table/#{@table}/999", %{"a" => 1}).status == 404
    assert call(:put, "/manage/api/table/#{@table}/999", %{"a" => 1}).status == 404
    assert call(:delete, "/manage/api/table/#{@table}/999").status == 404
  end

  test "credential-bearing tables are refused by the generic table routes" do
    for table <- ["webui_users", "webui_sessions"] do
      assert call(:get, "/manage/api/table/#{table}").status == 403
      assert call(:post, "/manage/api/table/#{table}", %{"x" => 1}).status == 403
      assert call(:delete, "/manage/api/table/#{table}").status == 403
      assert call(:get, "/manage/api/table/#{table}/1").status == 403
      assert call(:put, "/manage/api/table/#{table}/1", %{"x" => 1}).status == 403
      assert call(:patch, "/manage/api/table/#{table}/1", %{"x" => 1}).status == 403
      assert call(:delete, "/manage/api/table/#{table}/1").status == 403
    end

    # a normal table is unaffected
    assert call(:get, "/manage/api/table/#{@table}").status == 200
    assert call(:post, "/manage/api/table/#{@table}", %{"x" => 1}).status == 201
  end

  test "cards groups documents by card field" do
    DB.insert_with_id(@table, %{
      "card" => "E004010203040506",
      "version" => %{"2" => %{"name" => "ALICE"}, "10" => %{"name" => "ALICE10"}}
    })

    DB.insert_with_id("test_manage_plain", %{"card" => "E004010203040506"})

    conn = call(:get, "/manage/api/cards")
    assert conn.status == 200
    %{"cards" => [card]} = json(conn)

    assert card["card"] == "E004010203040506"

    entries = Enum.sort_by(card["entries"], & &1["table"])

    assert [
             %{"table" => "test_manage", "name" => "ALICE10"},
             %{"table" => "test_manage_plain", "name" => nil}
           ] = entries
  after
    DB.drop_table("test_manage_plain")
  end

  test "shop permit management" do
    # add a permitted shop
    conn = call(:post, "/manage/api/shops", %{"pcbid" => "SHOPTESTPCBID01", "opname" => "TEST SHOP"})
    assert conn.status == 201
    assert %{"pcbid" => "SHOPTESTPCBID01", "permitted" => true} = json(conn)

    # duplicate add conflicts
    assert call(:post, "/manage/api/shops", %{"pcbid" => "SHOPTESTPCBID01"}).status == 409
    # invalid pcbid rejected
    assert call(:post, "/manage/api/shops", %{"pcbid" => "bad pcbid!"}).status == 400
    assert call(:post, "/manage/api/shops", %{}).status == 400

    # listed
    conn = call(:get, "/manage/api/shops")
    assert %{"shops" => shops} = json(conn)
    assert Enum.any?(shops, &(&1["pcbid"] == "SHOPTESTPCBID01" and &1["permitted"] == true))

    # revoke / permit
    conn = call(:post, "/manage/api/shops/SHOPTESTPCBID01/revoke")
    assert json(conn)["permitted"] == false

    conn = call(:post, "/manage/api/shops/SHOPTESTPCBID01/permit")
    assert json(conn)["permitted"] == true

    # unknown pcbid 404s
    assert call(:post, "/manage/api/shops/MISSING/revoke").status == 404
    assert call(:post, "/manage/api/shops/MISSING/permit").status == 404
    assert call(:delete, "/manage/api/shops/MISSING").status == 404

    # delete removes the permission entirely
    assert call(:delete, "/manage/api/shops/SHOPTESTPCBID01").status == 204
    conn = call(:get, "/manage/api/shops")
    refute json(conn)["shops"] |> Enum.any?(&(&1["pcbid"] == "SHOPTESTPCBID01"))
  after
    DB.drop_table("shop")
  end

  test "user ban management" do
    DB.insert("webui_users", %{
      "username" => "villain",
      "pass_hash" => "AA",
      "salt" => "BB",
      "iterations" => 1,
      "cards" => ["E004000000000042"],
      "banned" => false,
      "created_at" => 1
    })

    DB.insert("webui_sessions", %{"token" => "tok1", "username" => "villain", "expires_at" => 9_999_999_999})

    # list hides credentials
    conn = call(:get, "/manage/api/users")
    assert %{"users" => [user]} = json(conn)
    assert user["username"] == "villain"
    assert user["banned"] == false
    refute Map.has_key?(user, "pass_hash")
    refute Map.has_key?(user, "salt")

    # ban kills live sessions
    conn = call(:post, "/manage/api/users/villain/ban")
    assert conn.status == 200
    assert json(conn)["banned"] == true
    assert DB.get("webui_sessions", %{"username" => "villain"}) == nil

    conn = call(:post, "/manage/api/users/villain/unban")
    assert json(conn)["banned"] == false

    assert call(:post, "/manage/api/users/ghost/ban").status == 404
    assert call(:post, "/manage/api/users/ghost/unban").status == 404
  after
    DB.drop_table("webui_users")
    DB.drop_table("webui_sessions")
  end

  test "webui serves static files" do
    dir = Path.join(System.tmp_dir!(), "bacon_webui_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "index.html"), "<html>webui</html>")

    old = Application.get_env(:bacon_net, :webui_dir)
    Application.put_env(:bacon_net, :webui_dir, dir)

    try do
      conn = call(:get, "/webui/")
      assert conn.status == 200
      assert conn.resp_body =~ "webui"

      conn = call(:get, "/webui")
      assert conn.status == 301
    after
      if old, do: Application.put_env(:bacon_net, :webui_dir, old),
        else: Application.delete_env(:bacon_net, :webui_dir)

      File.rm_rf!(dir)
    end
  end
end
