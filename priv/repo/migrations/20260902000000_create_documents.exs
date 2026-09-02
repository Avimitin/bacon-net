defmodule BaconNet.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents, primary_key: false) do
      add :table_name, :text, null: false
      add :doc_id, :text, null: false
      add :seq, :bigserial, null: false
      add :data, :map, null: false
      add :inserted_at, :utc_datetime_usec, null: false, default: fragment("now()")
    end

    create unique_index(:documents, [:table_name, :doc_id])
    create index(:documents, [:data], using: "GIN")
  end
end
