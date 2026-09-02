defmodule BaconNet.EacoinTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias BaconNet.{DB, Kbinxml, State, XNode}

  @pcbid "EACOINTESTPCBID1"
  @card "E004001122334455"

  setup do
    DB.upsert("shop", %{"pcbid" => @pcbid, "permitted" => true}, %{"pcbid" => @pcbid})
    DB.drop_table("paseli")
    State.put(:eacoin_payments, %{})
    State.put(:eacoin_sessid, 0)

    on_exit(fn ->
      DB.drop_table("paseli")
      DB.remove("shop", %{"pcbid" => @pcbid})
      State.put(:eacoin_payments, %{})
    end)

    :ok
  end

  defp call_eacoin(method, inner) do
    body = """
    <?xml version='1.0' encoding='UTF-8'?>
    <call model="LDJ:J:B:A:2024010100" srcid="#{@pcbid}">
      <eacoin method="#{method}">
        #{inner}
      </eacoin>
    </call>
    """

    conn(:post, "/core/test/eacoin/#{method}", body)
    |> Plug.Conn.put_req_header("content-length", to_string(byte_size(body)))
    |> BaconNet.Router.call(BaconNet.Router.init([]))
  end

  defp eacoin_node(conn) do
    assert conn.status == 200
    conn.resp_body |> Kbinxml.decode() |> Map.get(:node) |> XNode.child("eacoin")
  end

  defp node_int(node, tag) do
    node |> XNode.child(tag) |> Map.get(:text) |> String.to_integer()
  end

  defp checkin(card \\ @card) do
    conn = call_eacoin("checkin", ~s(<cardid __type="str">#{card}</cardid>))
    node = eacoin_node(conn)
    assert XNode.attr(node, "status") == nil
    node_int(node, "sessid")
  end

  defp consume(sessid, payment) do
    call_eacoin(
      "consume",
      ~s(<sessid __type="str">#{sessid}</sessid><payment __type="s32">#{payment}</payment>)
    )
  end

  defp getbalance(card \\ @card) do
    call_eacoin("getbalance", ~s(<cardid __type="str">#{card}</cardid>))
  end

  defp stored_balance(card \\ @card) do
    case DB.get("paseli", %{"cardid" => card}) do
      nil -> nil
      bal -> bal["balance"]
    end
  end

  test "checkin and consume debit the stored balance" do
    sessid = checkin()

    node = consume(sessid, 100) |> eacoin_node()
    assert XNode.attr(node, "status") == nil
    assert node_int(node, "balance") == 9_900
    assert stored_balance() == 9_900

    node = getbalance() |> eacoin_node()
    assert node_int(node, "balance") == 9_900
  end

  test "negative payment is rejected and does not change the balance" do
    sessid = checkin()

    node = consume(sessid, -500) |> eacoin_node()
    assert XNode.attr(node, "status") == "1"
    assert stored_balance() == nil
  end

  test "zero payment is rejected" do
    sessid = checkin()

    node = consume(sessid, 0) |> eacoin_node()
    assert XNode.attr(node, "status") == "1"
    assert stored_balance() == nil
  end

  test "oversized payment is rejected" do
    sessid = checkin()

    node = consume(sessid, 99_999) |> eacoin_node()
    assert XNode.attr(node, "status") == "1"
    assert stored_balance() == nil
  end

  test "consume without a session fails closed" do
    node = consume(999, 100) |> eacoin_node()
    assert XNode.attr(node, "status") == "1"
    assert stored_balance() == nil
  end

  test "getbalance requires a cardid" do
    node = call_eacoin("getbalance", "") |> eacoin_node()
    assert XNode.attr(node, "status") == "1"
  end

  test "checkout invalidates the session and repeated checkout errors" do
    sessid = checkin()

    node = call_eacoin("checkout", ~s(<sessid __type="str">#{sessid}</sessid>)) |> eacoin_node()
    assert XNode.attr(node, "status") == nil

    node = consume(sessid, 100) |> eacoin_node()
    assert XNode.attr(node, "status") == "1"

    node = call_eacoin("checkout", ~s(<sessid __type="str">#{sessid}</sessid>)) |> eacoin_node()
    assert XNode.attr(node, "status") == "1"
  end

  test "threshold reset is reflected in both response and storage" do
    DB.upsert("paseli", %{"cardid" => @card, "balance" => 1_500, "total_spent" => 0}, %{
      "cardid" => @card
    })

    sessid = checkin()

    node = consume(sessid, 600) |> eacoin_node()
    assert XNode.attr(node, "status") == nil
    assert node_int(node, "balance") == 10_000
    assert stored_balance() == 10_000
  end
end
