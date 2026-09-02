defmodule BaconNet.Modules.Core.Eacoin do
  @moduledoc "Port of modules/core/eacoin.py."

  alias BaconNet.{Config, Core, DB, E, State, XNode}

  def routes do
    %{
      prefix: "/core",
      tag: "eacoin",
      handlers: [
        {"eacoin", "checkin", :eacoin_checkin},
        {"eacoin", "checkout", :eacoin_checkout},
        {"eacoin", "consume", :eacoin_consume},
        {"eacoin", "getbalance", :eacoin_getbalance}
      ]
    }
  end

  def eacoin_checkin(conn) do
    {info, conn} = Core.process_request(conn)
    pcbid = XNode.attr(info.root, "srcid")
    cardid = Core.module_node(info) |> XNode.child("cardid") |> text()

    op = DB.get("shop", %{"pcbid" => pcbid}) || %{}
    bal = DB.get("paseli", %{"cardid" => cardid}) || %{}

    sessid =
      State.update(:eacoin_sessid, 0, fn s -> {s + 1, s + 1} end)

    State.update(:eacoin_payments, %{}, &{&1, Map.put(&1, sessid, cardid)})

    response =
      E.e("response",
        E.e("eacoin", [
          E.e("sequence", 1, __type: "s16"),
          E.e("acstatus", 1, __type: "u8"),
          E.e("acid", 1, __type: "str"),
          E.e("acname", Map.get(op, "opname", Config.arcade()), __type: "str"),
          E.e("balance", Map.get(bal, "balance", Config.paseli()), __type: "s32"),
          E.e("sessid", sessid, __type: "str"),
          E.e("inshopcharge", 1, __type: "u8")
        ])
      )

    Core.send_response(conn, info, response)
  end

  def eacoin_checkout(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("eacoin")))
  end

  def eacoin_consume(conn) do
    {info, conn} = Core.process_request(conn)
    node = Core.module_node(info)
    sessid = node |> XNode.child("sessid") |> text() |> String.to_integer()
    payment = node |> XNode.child("payment") |> text() |> String.to_integer()

    cardid = State.get(:eacoin_payments, %{}) |> Map.get(sessid)

    # fallback if server is restarted mid-round for IIDX movie or gacha purchases
    if cardid == nil do
      response =
        E.e("response",
          E.e("eacoin", [
            E.e("acstatus", 0, __type: "u8"),
            E.e("autocharge", 0, __type: "u8"),
            E.e("balance", Config.paseli(), __type: "s32")
          ])
        )

      Core.send_response(conn, info, response)
    else
      bal =
        DB.get("paseli", %{"cardid" => cardid}) ||
          %{"cardid" => cardid, "balance" => Config.paseli(), "total_spent" => 0}

      new_balance = bal["balance"] - payment

      paseli_card = %{
        "cardid" => cardid,
        "balance" => new_balance,
        "total_spent" => bal["total_spent"] + payment
      }

      response =
        E.e("response",
          E.e("eacoin", [
            E.e("acstatus", 0, __type: "u8"),
            E.e("autocharge", 0, __type: "u8"),
            E.e("balance", new_balance, __type: "s32")
          ])
        )

      paseli_card =
        if new_balance < 1000 or new_balance > Config.paseli() do
          %{paseli_card | "balance" => Config.paseli()}
        else
          paseli_card
        end

      DB.upsert("paseli", paseli_card, %{"cardid" => cardid})

      Core.send_response(conn, info, response)
    end
  end

  def eacoin_getbalance(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e("response",
        E.e("eacoin", [
          E.e("acstatus", 0, __type: "u8"),
          E.e("balance", Config.paseli(), __type: "s32")
        ])
      )

    Core.send_response(conn, info, response)
  end

  defp text(nil), do: nil
  defp text(%XNode{text: t}), do: t
end
