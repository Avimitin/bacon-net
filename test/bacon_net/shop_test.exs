defmodule BaconNet.ShopTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias BaconNet.{DB, E, Kbinxml, Shop, XNode}

  @model "LDJ:J:A:A:2025091700"

  setup do
    DB.drop_table("shop")
    on_exit(fn -> DB.drop_table("shop") end)
    :ok
  end

  defp kbin_post(path, module_node, pcbid) do
    attrs = if pcbid, do: [model: @model, srcid: pcbid], else: [model: @model]
    body = Kbinxml.encode(E.e("call", module_node, attrs))

    conn(:post, path, body)
    |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
    |> Plug.Conn.put_req_header("content-length", to_string(byte_size(body)))
    |> BaconNet.Router.call(BaconNet.Router.init([]))
  end

  defp services_get(pcbid) do
    kbin_post("/core/#{@model}/services/get", E.e("services", method: "get"), pcbid)
  end

  defp status_of(conn) do
    assert conn.status == 200
    root = Kbinxml.decode(conn.resp_body).node
    module_node = root.children |> List.first()
    {module_node.tag, XNode.attr(module_node, "status")}
  end

  test "requests without a permitted PCBID are rejected" do
    conn = services_get("UNKNOWNPCBID001")
    assert {"services", "1"} = status_of(conn)

    # the unknown PCBID is remembered as a pending shop
    assert %{"permitted" => false} = DB.get("shop", %{"pcbid" => "UNKNOWNPCBID001"})
  end

  test "requests without any PCBID are rejected" do
    conn = services_get(nil)
    assert {"services", "1"} = status_of(conn)
  end

  test "permitted shops get the full services list" do
    {:ok, _} = Shop.permit("PERMITTEDPCBID01")

    conn = services_get("PERMITTEDPCBID01")
    assert {"services", nil} = status_of(conn)

    root = Kbinxml.decode(conn.resp_body).node
    services = XNode.child(root, "services")
    items = XNode.children(services, "item") |> Enum.map(&XNode.attr(&1, "name"))
    assert "facility" in items
  end

  test "legacy shop documents without the permitted flag still connect" do
    DB.insert("shop", %{"pcbid" => "LEGACYPCBID00001", "opname" => "OLD SHOP"})
    assert Shop.permitted?("LEGACYPCBID00001")

    conn = services_get("LEGACYPCBID00001")
    assert {"services", nil} = status_of(conn)
  end

  test "revoked shops are rejected again" do
    {:ok, _} = Shop.permit("REVOKEDPCBID0001")
    assert {"services", nil} = status_of(services_get("REVOKEDPCBID0001"))

    :ok = Shop.revoke("REVOKEDPCBID0001")
    assert {"services", "1"} = status_of(services_get("REVOKEDPCBID0001"))
  end

  test "game protocol routes are guarded too" do
    conn =
      kbin_post(
        "/local/#{@model}/IIDX33pc/common",
        E.e("IIDX33pc", method: "common"),
        "UNKNOWNPCBID002"
      )

    assert {"IIDX33pc", "1"} = status_of(conn)

    {:ok, _} = Shop.permit("UNKNOWNPCBID002")

    conn =
      kbin_post(
        "/local/#{@model}/IIDX33pc/common",
        E.e("IIDX33pc", method: "common"),
        "UNKNOWNPCBID002"
      )

    assert {"IIDX33pc", nil} = status_of(conn)
  end

  test "slashless forwarder is guarded" do
    conn =
      kbin_post(
        "/fwdr?model=#{@model}&f=IIDX33pc.common",
        E.e("IIDX33pc", method: "common"),
        "UNKNOWNPCBID003"
      )

    assert {"IIDX33pc", "1"} = status_of(conn)
  end

  test "register_pending and revoke/delete on missing shops" do
    assert :ok = Shop.register_pending("PENDINGPCBID0001")
    assert :ok = Shop.register_pending("PENDINGPCBID0001")
    assert %{"permitted" => false} = DB.get("shop", %{"pcbid" => "PENDINGPCBID0001"})

    assert :not_found = Shop.revoke("MISSINGPCBID0001")
    assert :not_found = Shop.delete("MISSINGPCBID0001")

    assert {:error, :invalid_pcbid} = Shop.permit("bad pcbid!")
  end
end
