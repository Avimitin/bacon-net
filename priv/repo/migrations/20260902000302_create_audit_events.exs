defmodule BaconNet.Repo.Migrations.CreateAuditEvents do
  use Ecto.Migration

  def change do
    create table(:audit_events) do
      add(:actor, :text, null: false)
      add(:action, :text, null: false)
      add(:target, :text)
      add(:outcome, :text, null: false)
      add(:request_id, :text)
      add(:metadata, :map, null: false, default: %{})
      add(:created_at, :utc_datetime_usec, null: false, default: fragment("now()"))
    end

    create(index(:audit_events, [:action]))
    create(index(:audit_events, [:created_at]))
  end
end
