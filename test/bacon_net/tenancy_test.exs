defmodule BaconNet.TenancyTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias BaconNet.{E, Kbinxml, Repo, RequestContext, Shop, Tenancy, XNode}

  @model "LDJ:J:A:A:2025091700"

  setup do
    clean()
    on_exit(&clean/0)
    :ok
  end

  defp clean do
    Repo.delete_all(Tenancy.Cabinet)
  end

  defp services_get(pcbid, model \\ @model) do
    body = Kbinxml.encode(E.e("call", E.e("services", method: "get"), model: model, srcid: pcbid))

    conn(:post, "/core/#{model}/services/get", body)
    |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
    |> Plug.Conn.put_req_header("content-length", to_string(byte_size(body)))
    |> BaconNet.Router.call(BaconNet.Router.init([]))
  end

  defp status_of(conn) do
    assert conn.status == 200
    root = Kbinxml.decode(conn.resp_body).node
    module_node = root.children |> List.first()
    XNode.attr(module_node, "status")
  end

  test "resolve_cabinet fails closed for unknown, pending and revoked" do
    assert {:error, :unknown} = Tenancy.resolve_cabinet("TENANCYUNKNOWN01")

    :ok = Tenancy.register_pending("TENANCYUNKNOWN01")
    assert {:error, :pending} = Tenancy.resolve_cabinet("TENANCYUNKNOWN01")

    {:ok, _} = Tenancy.permit("TENANCYUNKNOWN01")

    assert {:ok, %Tenancy.Cabinet{state: "permitted"}} =
             Tenancy.resolve_cabinet("TENANCYUNKNOWN01")

    :ok = Tenancy.revoke("TENANCYUNKNOWN01")
    assert {:error, :revoked} = Tenancy.resolve_cabinet("TENANCYUNKNOWN01")
  end

  test "revocation takes effect immediately and stamps revoked_at" do
    {:ok, _} = Shop.permit("TENANCYREVOKE01")
    assert status_of(services_get("TENANCYREVOKE01")) == nil

    :ok = Shop.revoke("TENANCYREVOKE01")

    cabinet = Tenancy.get_cabinet("TENANCYREVOKE01")
    assert cabinet.state == "revoked"
    assert %DateTime{} = cabinet.revoked_at

    # the very next request is rejected
    assert status_of(services_get("TENANCYREVOKE01")) == "1"

    # and permit re-opens a revoked cabinet
    {:ok, _} = Shop.permit("TENANCYREVOKE01")
    cabinet = Tenancy.get_cabinet("TENANCYREVOKE01")
    assert cabinet.state == "permitted"
    assert cabinet.revoked_at == nil
    assert status_of(services_get("TENANCYREVOKE01")) == nil
  end

  test "body PCBID cannot impersonate another cabinet's identity" do
    {:ok, %{}} = Shop.permit("TENANCYPCBIDA01")
    {:ok, %{}} = Shop.permit("TENANCYPCBIDB01")

    conn = services_get("TENANCYPCBIDA01")
    assert status_of(conn) == nil

    ctx = RequestContext.get(conn)
    assert ctx.pcbid == "TENANCYPCBIDA01"
    assert ctx.cabinet_id == Tenancy.get_cabinet("TENANCYPCBIDA01").id
    assert ctx.cabinet_id != Tenancy.get_cabinet("TENANCYPCBIDB01").id

    # an unpermitted body PCBID gets no context at all
    conn = services_get("TENANCYPCBIDC01")
    assert status_of(conn) == "1"
    assert RequestContext.get(conn) == nil
  end

  test "request context carries game and version derived from the model" do
    {:ok, _} = Shop.permit("TENANCYVERSION01")

    conn = services_get("TENANCYVERSION01", "LDJ:J:A:A:2025091700")
    ctx = RequestContext.get(conn)
    assert ctx.game == "LDJ"
    assert ctx.version == 33
    assert is_binary(ctx.request_id)
  end

  test "cabinet rejections emit a telemetry event with the reason" do
    test_pid = self()

    :telemetry.attach(
      {__MODULE__, :reject_listener},
      [:bacon_net, :cabinet, :rejected],
      fn _event, measurements, metadata, _ ->
        send(test_pid, {:cabinet_rejected, measurements, metadata})
      end,
      nil
    )

    {:ok, _} = Shop.permit("TENANCYTELEM001")
    :ok = Shop.revoke("TENANCYTELEM001")

    services_get("TENANCYTELEM001")

    assert_received {:cabinet_rejected, %{count: 1},
                     %{reason: :revoked, pcbid: "TENANCYTELEM001"}}

    services_get("TENANCYTELEM999")

    assert_received {:cabinet_rejected, %{count: 1},
                     %{reason: :unknown, pcbid: "TENANCYTELEM999"}}

    :telemetry.detach({__MODULE__, :reject_listener})
  end

  test "pending cabinets are filed under the default network and shop" do
    :ok = Tenancy.register_pending("TENANCYDEFAULT1")

    cabinet = Tenancy.get_cabinet("TENANCYDEFAULT1")
    assert cabinet.state == "pending"
    assert cabinet.shop.name == "default"
    assert cabinet.shop.network.name == "default"
  end
end
