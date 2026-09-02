defmodule BaconNet.Repo.Migrations.CreateTenancy do
  use Ecto.Migration

  def change do
    create table(:networks) do
      add(:name, :text, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:networks, [:name]))

    create table(:shops) do
      add(:network_id, references(:networks, on_delete: :restrict), null: false)
      add(:name, :text, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:shops, [:network_id, :name]))

    create table(:cabinets) do
      add(:shop_id, references(:shops, on_delete: :restrict), null: false)
      add(:pcbid, :text, null: false)
      add(:state, :text, null: false, default: "pending")
      add(:label, :text)
      add(:revoked_at, :utc_datetime_usec)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:cabinets, [:pcbid]))
    create(index(:cabinets, [:state]))
  end
end
