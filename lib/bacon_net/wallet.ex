defmodule BaconNet.Wallet.Account do
  @moduledoc """
  Rollup row for one card's wallet. The balance here is a cache of the
  `wallet_entries` ledger sum, updated in the same transaction as every
  entry; the row is locked `FOR UPDATE` while a debit settles, so concurrent
  debits serialize and can never double-spend.
  """
  use Ecto.Schema

  schema "wallets" do
    field(:card_id, :string)
    field(:balance, :integer)
    field(:total_spent, :integer)
    has_many(:entries, BaconNet.Wallet.Entry, foreign_key: :card_id, references: :card_id)

    timestamps(type: :utc_datetime_usec)
  end
end

defmodule BaconNet.Wallet.Entry do
  @moduledoc """
  One ledger entry. Debits are negative, credits (init/top-up/adjustment)
  positive; `txn_key` is globally unique so a repeated request can be
  recognized and answered from `balance_after` without a second entry.
  """
  use Ecto.Schema

  schema "wallet_entries" do
    field(:card_id, :string)
    field(:session_id, :string)
    field(:amount, :integer)
    field(:kind, :string)
    field(:txn_key, :string)
    field(:balance_after, :integer)
    field(:created_at, :utc_datetime_usec)
  end
end

defmodule BaconNet.Wallet do
  @moduledoc """
  Ledger-grade PASELI wallet.

  Every balance change is a row in `wallet_entries`; the `wallets` rollup row
  carries the cached balance and is updated in the same transaction as the
  entry, so the reported balance always reconciles with the ledger sum. A
  card without a wallet row yet reports the configured starting balance
  (`Config.paseli()`); the row and its opening `init` credit are materialized
  by the first debit or explicit adjustment, from which point
  `balance/1 == ledger_sum/1` holds exactly.

  The emulator's threshold rule is preserved: when a debit would move the
  balance out of the 1000..cap band, an explicit `topup` credit entry in the
  same transaction brings it back to the configured balance, so balances can
  never go negative.

  Duplicate safety: `debit/4` keys its ledger entry on `txn_key` (derived
  from session + payment + request body hash); a repeated identical consume
  returns the prior outcome (`balance_after` of the existing entry) without
  writing a second entry.
  """

  import Ecto.Changeset
  import Ecto.Query

  alias BaconNet.{Config, Repo}
  alias BaconNet.Wallet.{Account, Entry}

  # Balance floor of the auto-top-up band (emulator rule from eacoin.py).
  @topup_threshold 1000

  @doc "The wallet rollup row for a card, or nil when never materialized."
  def account(card_id), do: Repo.get_by(Account, card_id: card_id)

  @doc "Reported balance: the rollup balance, or the configured start for new cards."
  def balance(card_id) do
    case account(card_id) do
      nil -> Config.paseli()
      %Account{balance: balance} -> balance
    end
  end

  @doc "Sum of ledger entries for a card."
  def ledger_sum(card_id) do
    case Repo.aggregate(from(e in Entry, where: e.card_id == ^card_id), :sum, :amount) do
      nil -> 0
      %Decimal{} = sum -> Decimal.to_integer(sum)
      sum -> sum
    end
  end

  @doc "All ledger entries for a card, oldest first."
  def entries(card_id) do
    Repo.all(from(e in Entry, where: e.card_id == ^card_id, order_by: [asc: e.id]))
  end

  @doc """
  Idempotency key for a consume: session + payment + a hash of the request
  body, so a byte-identical replay maps to the same key.
  """
  def txn_key(session_id, payment, body_text) do
    hash = :crypto.hash(:sha256, body_text || "") |> Base.encode16(case: :lower)
    "consume:#{session_id}:#{payment}:#{hash}"
  end

  @doc """
  Debit `amount` (positive integer) from a card's wallet. Returns
  {:ok, balance_after} or {:error, reason}. The balance check, entry insert,
  and rollup update happen in one transaction holding a FOR UPDATE lock on
  the rollup row, so concurrent debits serialize and never double-spend; a
  repeated `txn_key` returns the prior outcome without a second entry.
  """
  def debit(card_id, amount, session_id, txn_key)
      when is_binary(card_id) and is_integer(amount) and amount > 0 do
    Repo.transaction(fn ->
      account = lock_account(card_id)

      case Repo.get_by(Entry, txn_key: txn_key) do
        %Entry{card_id: ^card_id, balance_after: balance_after} ->
          # Identical consume seen before: replay the prior outcome.
          balance_after

        %Entry{} ->
          # Same key, different card: the key derivation was violated.
          Repo.rollback(:txn_key_conflict)

        nil ->
          apply_debit(account, amount, session_id, txn_key)
      end
    end)
  end

  def debit(_, _, _, _), do: {:error, :invalid_payment}

  @doc """
  Force a card's balance to `amount` via an explicit adjustment entry
  (admin/test tooling; the ledger stays reconciled).
  """
  def set_balance(card_id, amount) when is_binary(card_id) and is_integer(amount) do
    Repo.transaction(fn ->
      account = lock_account(card_id)
      diff = amount - account.balance

      if diff != 0 do
        insert_entry!(%{
          card_id: card_id,
          session_id: nil,
          amount: diff,
          kind: "adjustment",
          txn_key: "adjust:#{card_id}:#{System.unique_integer([:positive])}",
          balance_after: amount
        })
      end

      account |> change(balance: amount) |> Repo.update!()
      amount
    end)
  end

  ## Internals

  defp apply_debit(account, amount, session_id, txn_key) do
    new_balance = account.balance - amount

    insert_entry!(%{
      card_id: account.card_id,
      session_id: session_id,
      amount: -amount,
      kind: "debit",
      txn_key: txn_key,
      balance_after: new_balance
    })

    settled = settle(account, new_balance, session_id, txn_key)

    account
    |> change(balance: settled, total_spent: account.total_spent + amount)
    |> Repo.update!()

    settled
  end

  # Threshold reset rule: a balance leaving the 1000..cap band is topped back
  # up to the configured balance with an explicit credit entry.
  defp settle(account, new_balance, session_id, txn_key) do
    if new_balance < @topup_threshold or new_balance > Config.paseli() do
      settled = Config.paseli()

      insert_entry!(%{
        card_id: account.card_id,
        session_id: session_id,
        amount: settled - new_balance,
        kind: "topup",
        txn_key: "#{txn_key}:topup",
        balance_after: settled
      })

      settled
    else
      new_balance
    end
  end

  # Get-or-create the rollup row, then lock it FOR UPDATE for the rest of the
  # transaction. The creator (and only it) observes an entry-less account and
  # adopts its starting balance as the opening `init` credit; concurrent
  # creators serialize on the card_id unique index and then on the row lock.
  defp lock_account(card_id) do
    Repo.insert(%Account{card_id: card_id, balance: Config.paseli(), total_spent: 0},
      on_conflict: :nothing,
      conflict_target: :card_id
    )

    account = Repo.one!(from(a in Account, where: a.card_id == ^card_id, lock: "FOR UPDATE"))

    unless Repo.exists?(from(e in Entry, where: e.card_id == ^card_id)) do
      insert_entry!(%{
        card_id: card_id,
        session_id: nil,
        amount: account.balance,
        kind: "init",
        txn_key: "init:#{card_id}",
        balance_after: account.balance
      })
    end

    account
  end

  defp insert_entry!(attrs) do
    Repo.insert!(struct(Entry, attrs))
  end
end
