defmodule BaconNet.Repo.Migrations.CreateWalletLedger do
  use Ecto.Migration

  def change do
    create table(:wallets) do
      add(:card_id, :text, null: false)
      add(:balance, :bigint, null: false, default: 0)
      add(:total_spent, :bigint, null: false, default: 0)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:wallets, [:card_id]))

    create table(:wallet_entries) do
      add(:card_id, :text, null: false)
      add(:session_id, :text)
      add(:amount, :bigint, null: false)
      add(:kind, :text, null: false)
      add(:txn_key, :text, null: false)
      add(:balance_after, :bigint, null: false)
      add(:created_at, :utc_datetime_usec, null: false, default: fragment("now()"))
    end

    create(unique_index(:wallet_entries, [:txn_key]))
    create(index(:wallet_entries, [:card_id]))
  end
end
