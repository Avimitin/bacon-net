defmodule BaconNet.ManageTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias BaconNet.DB

  @table "test_manage"

  setup do
    DB.drop_table(@table)
    on_exit(fn -> DB.drop_table(@table) end)
    :ok
  end

  defp call(method, path, body \\ nil) do
    conn =
      if body do
        conn(method, path, Jason.encode!(body))
        |> Plug.Conn.put_req_header("content-type", "application/json")
      else
        conn(method, path)
      end

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
