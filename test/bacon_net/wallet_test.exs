defmodule BaconNet.WalletTest do
  use ExUnit.Case, async: false

  alias BaconNet.{Config, Repo, Wallet}

  @card "WALLETTESTCARD001"

  setup do
    clean()
    on_exit(&clean/0)
    :ok
  end

  defp clean do
    Repo.delete_all(Wallet.Entry)
    Repo.delete_all(Wallet.Account)
  end

  test "fresh cards report the configured starting balance" do
    assert Wallet.account(@card) == nil
    assert Wallet.balance(@card) == Config.paseli()
  end

  test "debit writes a ledger entry and the balance reconciles with the ledger" do
    assert {:ok, 9_900} = Wallet.debit(@card, 100, "1", "test:debit:1")

    assert Wallet.balance(@card) == 9_900
    assert Wallet.ledger_sum(@card) == 9_900

    entries = Wallet.entries(@card)
    assert [%{kind: "init", amount: 10_000}, %{kind: "debit", amount: -100}] = entries
  end

  test "duplicate txn key returns the prior outcome without a second entry" do
    assert {:ok, 9_900} = Wallet.debit(@card, 100, "1", "test:dup:1")
    assert {:ok, 9_900} = Wallet.debit(@card, 100, "1", "test:dup:1")
    assert {:ok, 9_900} = Wallet.debit(@card, 999, "1", "test:dup:1")

    # one init + one debit; the replayed balance does not move
    assert Enum.map(Wallet.entries(@card), & &1.kind) == ["init", "debit"]
    assert Wallet.balance(@card) == 9_900
    assert Wallet.ledger_sum(@card) == 9_900
  end

  test "a txn key used by another card conflicts" do
    assert {:ok, _} = Wallet.debit(@card, 100, "1", "test:conflict:1")

    assert {:error, :txn_key_conflict} =
             Wallet.debit("WALLETTESTCARD002", 100, "1", "test:conflict:1")
  end

  test "auto top-up is an explicit credit entry" do
    {:ok, 1_500} = Wallet.set_balance(@card, 1_500)

    assert {:ok, 10_000} = Wallet.debit(@card, 600, "9", "test:topup:1")

    entries = Wallet.entries(@card)
    assert %{kind: "topup", amount: 9_100, balance_after: 10_000} = List.last(entries)
    assert Wallet.balance(@card) == 10_000
    assert Wallet.ledger_sum(@card) == 10_000
  end

  test "a rolled back transaction leaves no entry and no account" do
    assert {:error, :forced} =
             Repo.transaction(fn ->
               {:ok, _} = Wallet.debit(@card, 100, "1", "test:rollback:1")
               Repo.rollback(:forced)
             end)

    assert Wallet.entries(@card) == []
    assert Wallet.account(@card) == nil
  end

  test "concurrent debits serialize: no overspend, ledger matches balance" do
    n = 8
    barrier = :counters.new(1, [])

    tasks =
      for i <- 1..n do
        Task.async(fn ->
          :counters.add(barrier, 1, 1)
          await_barrier(barrier, n)
          Wallet.debit(@card, 100, "sess-#{i}", "test:concurrent:#{i}")
        end)
      end

    results = Task.await_many(tasks, 30_000)
    assert Enum.all?(results, &match?({:ok, _}, &1))

    # every debit was applied exactly once; no balance was double-spent
    debits = Enum.filter(Wallet.entries(@card), &(&1.kind == "debit"))
    assert length(debits) == n
    assert length(Enum.uniq_by(debits, & &1.txn_key)) == n

    assert Wallet.balance(@card) == Config.paseli() - 100 * n
    assert Wallet.ledger_sum(@card) == Config.paseli() - 100 * n
    assert Wallet.balance(@card) >= 0
  end

  test "concurrent duplicate consumes produce exactly one entry" do
    n = 6
    barrier = :counters.new(1, [])

    tasks =
      for _ <- 1..n do
        Task.async(fn ->
          :counters.add(barrier, 1, 1)
          await_barrier(barrier, n)
          Wallet.debit(@card, 100, "sess", "test:concurrent-dup:1")
        end)
      end

    results = Task.await_many(tasks, 30_000)
    assert Enum.all?(results, &(&1 == {:ok, 9_900}))

    assert [%{kind: "debit"}] = Enum.filter(Wallet.entries(@card), &(&1.kind == "debit"))
    assert Wallet.balance(@card) == 9_900
    assert Wallet.ledger_sum(@card) == 9_900
  end

  # Busy barrier: all tasks line up before any debit starts, no sleeps.
  defp await_barrier(counter, n) do
    if :counters.get(counter, 1) < n, do: await_barrier(counter, n)
  end
end
