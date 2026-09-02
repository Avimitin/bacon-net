defmodule BaconNet.Repo.Migrations.AddDocumentsPaginationIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    # Keyset pagination over documents orders by seq; this keeps
    # `ORDER BY seq ... LIMIT n` bounded instead of a full sort.
    create(index(:documents, [:seq], concurrently: true))
  end
end
