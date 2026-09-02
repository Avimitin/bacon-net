defmodule BaconNet.DdrPlayerdataTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias BaconNet.{DB, E, Kbinxml, Shop, XNode}

  @model "MDX:J:A:A:2019022600"

  setup do
    DB.drop_table("shop")
    DB.drop_table("ddr_profile")
    {:ok, _} = Shop.permit("DDRTESTPCBID0001")

    on_exit(fn ->
      DB.drop_table("shop")
      DB.drop_table("ddr_profile")
    end)

    :ok
  end

  defp kbin_post(path, module_node) do
    body = Kbinxml.encode(E.e("call", module_node, model: @model, srcid: "DDRTESTPCBID0001"))

    conn(:post, path, body)
    |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
    |> Plug.Conn.put_req_header("content-length", to_string(byte_size(body)))
    |> BaconNet.Router.call(BaconNet.Router.init([]))
  end

  test "usergamedata_recv for an unknown card returns a protocol error, not a 500" do
    conn =
      kbin_post(
        "/local2/#{@model}/playerdata/usergamedata_recv",
        E.e("playerdata", [E.e("data", E.e("refid", "E004009999999999"))],
          method: "usergamedata_recv"
        )
      )

    assert conn.status == 200
    root = Kbinxml.decode(conn.resp_body).node
    result = root |> XNode.child("playerdata") |> XNode.child("result")
    assert result.text == "1"
  end

  test "usergamedata_recv without a refid returns a protocol error, not a 500" do
    conn =
      kbin_post(
        "/local2/#{@model}/playerdata/usergamedata_recv",
        E.e("playerdata", method: "usergamedata_recv", refid: "E004009999999999")
      )

    assert conn.status == 200
    root = Kbinxml.decode(conn.resp_body).node
    result = root |> XNode.child("playerdata") |> XNode.child("result")
    assert result.text == "1"
  end
end
