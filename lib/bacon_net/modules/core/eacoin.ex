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
      E.e(
        "response",
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
    sessid = info |> Core.module_node() |> XNode.child("sessid") |> text() |> parse_int()

    if sessid != nil and Map.has_key?(State.get(:eacoin_payments, %{}), sessid) do
      State.update(:eacoin_payments, %{}, &{&1, Map.delete(&1, sessid)})
      Core.send_response(conn, info, E.e("response", E.e("eacoin")))
    else
      error_response(conn, info)
    end
  end

  def eacoin_consume(conn) do
    {info, conn} = Core.process_request(conn)
    node = Core.module_node(info)
    sessid = node |> XNode.child("sessid") |> text() |> parse_int()
    payment = node |> XNode.child("payment") |> text() |> parse_int()

    cardid = sessid && State.get(:eacoin_payments, %{}) |> Map.get(sessid)

    cond do
      # fail closed: no session, no funds
      cardid == nil ->
        error_response(conn, info)

      not valid_payment?(payment) ->
        error_response(conn, info)

      true ->
        bal =
          DB.get("paseli", %{"cardid" => cardid}) ||
            %{"cardid" => cardid, "balance" => Config.paseli(), "total_spent" => 0}

        new_balance = settle_balance(bal["balance"] - payment)

        DB.upsert(
          "paseli",
          %{
            "cardid" => cardid,
            "balance" => new_balance,
            "total_spent" => bal["total_spent"] + payment
          },
          %{"cardid" => cardid}
        )

        response =
          E.e(
            "response",
            E.e("eacoin", [
              E.e("acstatus", 0, __type: "u8"),
              E.e("autocharge", 0, __type: "u8"),
              E.e("balance", new_balance, __type: "s32")
            ])
          )

        Core.send_response(conn, info, response)
    end
  end

  def eacoin_getbalance(conn) do
    {info, conn} = Core.process_request(conn)
    cardid = Core.module_node(info) |> XNode.child("cardid") |> text()

    if cardid do
      balance =
        case DB.get("paseli", %{"cardid" => cardid}) do
          nil -> Config.paseli()
          bal -> bal["balance"]
        end

      response =
        E.e(
          "response",
          E.e("eacoin", [
            E.e("acstatus", 0, __type: "u8"),
            E.e("balance", balance, __type: "s32")
          ])
        )

      Core.send_response(conn, info, response)
    else
      error_response(conn, info)
    end
  end

  # A payment is a positive integer no larger than the configured balance
  # cap (balances never exceed it, see settle_balance/1).
  defp valid_payment?(payment) do
    is_integer(payment) and payment > 0 and payment <= Config.paseli()
  end

  # Threshold reset rule: a balance leaving the 1000..cap band is topped
  # back up to the configured balance. Applied before responding so the
  # reported balance always matches the stored one.
  defp settle_balance(balance) do
    if balance < 1000 or balance > Config.paseli(), do: Config.paseli(), else: balance
  end

  defp error_response(conn, info) do
    Core.send_response(conn, info, E.e("response", E.e("eacoin", status: 1)))
  end

  defp text(nil), do: nil
  defp text(%XNode{text: t}), do: t

  defp parse_int(nil), do: nil

  defp parse_int(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end
end
