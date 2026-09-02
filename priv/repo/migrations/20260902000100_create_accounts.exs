defmodule BaconNet.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add(:username, :text, null: false)
      add(:display_name, :text)
      add(:pass_hash, :text, null: false)
      add(:salt, :text, null: false)
      add(:iterations, :integer, null: false)
      add(:banned, :boolean, null: false, default: false)
      add(:admin, :boolean, null: false, default: false)

      timestamps(type: :utc_datetime_usec)
    end

    # Case-insensitive uniqueness: concurrent registrations of differently
    # cased spellings of the same username cannot both commit.
    create(unique_index(:accounts, ["lower(username)"], name: :accounts_username_lower_index))

    create table(:account_sessions) do
      add(:account_id, references(:accounts, on_delete: :delete_all), null: false)
      add(:token_digest, :text, null: false)
      add(:last_used_at, :bigint, null: false)
      add(:expires_at, :bigint, null: false)
      add(:revoked, :boolean, null: false, default: false)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:account_sessions, [:token_digest]))
    create(index(:account_sessions, [:account_id]))
    create(index(:account_sessions, [:expires_at]))

    create table(:account_cards) do
      add(:account_id, references(:accounts, on_delete: :delete_all), null: false)
      add(:card_uid, :text, null: false)
      add(:konami_id, :text)

      timestamps(type: :utc_datetime_usec)
    end

    # One card has exactly one owner, enforced by the database so concurrent
    # binds from two accounts cannot both succeed.
    create(unique_index(:account_cards, [:card_uid]))
    create(index(:account_cards, [:account_id]))
  end
end
