defmodule BaconNet.Repo.Migrations.CreateScoresTables do
  use Ecto.Migration

  def change do
    create table(:play_attempts) do
      add(:game, :text, null: false)
      add(:version, :integer, null: false)
      add(:player, :text, null: false)
      add(:song, :bigint, null: false)
      add(:chart, :bigint, null: false)
      add(:play_style, :text, null: false, default: "")
      add(:score, :bigint)
      add(:clear, :integer)
      add(:miss, :integer)
      add(:payload, :map, null: false)
      add(:created_at, :utc_datetime_usec, null: false, default: fragment("now()"))
    end

    create(index(:play_attempts, [:game, :player]))
    create(index(:play_attempts, [:game, :song, :chart]))

    create table(:best_scores) do
      add(:game, :text, null: false)
      add(:player, :text, null: false)
      add(:song, :bigint, null: false)
      add(:chart, :bigint, null: false)
      add(:play_style, :text, null: false, default: "")
      add(:version, :integer, null: false)
      add(:score, :bigint, null: false, default: 0)
      add(:clear, :integer, null: false, default: 0)
      add(:miss, :integer)
      add(:payload, :map, null: false, default: %{})
      add(:inserted_at, :utc_datetime_usec, null: false, default: fragment("now()"))
      add(:updated_at, :utc_datetime_usec, null: false, default: fragment("now()"))
    end

    create(unique_index(:best_scores, [:game, :player, :song, :chart, :play_style]))

    create table(:score_stats) do
      add(:game, :text, null: false)
      add(:song, :bigint, null: false)
      add(:chart, :bigint, null: false)
      add(:play_style, :text, null: false, default: "")
      add(:play_count, :bigint, null: false, default: 0)
      add(:clear_count, :bigint, null: false, default: 0)
      add(:fc_count, :bigint, null: false, default: 0)
      add(:updated_at, :utc_datetime_usec, null: false, default: fragment("now()"))
    end

    create(unique_index(:score_stats, [:game, :song, :chart, :play_style]))

    create table(:idempotency_keys) do
      add(:key, :text, null: false)
      add(:scope, :text, null: false)
      add(:payload_hash, :text, null: false)
      add(:response, :map)
      add(:created_at, :utc_datetime_usec, null: false, default: fragment("now()"))
    end

    create(unique_index(:idempotency_keys, [:key]))

    create table(:outbox_events) do
      add(:topic, :text, null: false)
      add(:payload, :map, null: false)
      add(:created_at, :utc_datetime_usec, null: false, default: fragment("now()"))
      add(:published_at, :utc_datetime_usec)
    end

    create(index(:outbox_events, [:published_at]))
  end
end
