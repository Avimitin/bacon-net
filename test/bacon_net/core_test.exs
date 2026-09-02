defmodule BaconNet.CoreTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias BaconNet.{DB, E, Kbinxml, Shop}

  @model "LDJ:J:A:A:2025091700"
  @path "/core/#{@model}/services/get"

  setup do
    DB.drop_table("shop")
    {:ok, _} = Shop.permit("CORETESTPCBID001")
    on_exit(fn -> DB.drop_table("shop") end)
    :ok
  end

  defp post_raw(path, body, headers) do
    conn = conn(:post, path, body)

    headers
    |> Enum.reduce(conn, fn {k, v}, c -> Plug.Conn.put_req_header(c, k, v) end)
    |> Plug.Conn.put_req_header("content-length", to_string(byte_size(body)))
    |> BaconNet.Router.call(BaconNet.Router.init([]))
  end

  defp services_body do
    Kbinxml.encode(E.e("call", E.e("services", method: "get"), model: @model, srcid: "CORETESTPCBID001"))
  end

  test "garbage body returns 400 instead of crashing" do
    conn = post_raw(@path, "this is not kbin or xml", [])
    assert conn.status == 400
  end

  test "truncated kbin returns 400" do
    conn = post_raw(@path, binary_part(services_body(), 0, 12), [])
    assert conn.status == 400
  end

  test "non-numeric content-length returns 400" do
    body = services_body()

    conn =
      conn(:post, @path, body)
      |> Plug.Conn.put_req_header("content-length", "not-a-number")
      |> BaconNet.Router.call(BaconNet.Router.init([]))

    assert conn.status == 400
  end

  test "malformed x-eamuse-info header returns 400" do
    conn = post_raw(@path, services_body(), [{"x-eamuse-info", "bogus"}])
    assert conn.status == 400
  end

  test "invalid hex in x-eamuse-info returns 400" do
    conn = post_raw(@path, services_body(), [{"x-eamuse-info", "1-zzzz-1"}])
    assert conn.status == 400
  end

  test "decompressed body over the cap returns 413" do
    Application.put_env(:bacon_net, :max_decompressed_body, 16)

    try do
      body = BaconNet.LZ77.encode(services_body())
      conn = post_raw(@path, body, [{"x-compress", "lz77"}])
      assert conn.status == 413
    after
      Application.delete_env(:bacon_net, :max_decompressed_body)
    end
  end

  test "well-formed requests are unaffected" do
    conn = post_raw(@path, services_body(), [])
    assert conn.status == 200
    assert Kbinxml.is_binary_xml(conn.resp_body)
  end
end
