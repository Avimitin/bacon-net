defmodule BaconNet.DB do
  @moduledoc """
  TinyDB-compatible document store backed by PostgreSQL.

  Documents live in the `documents` table as JSONB keyed by
  `{table_name, doc_id}`; `seq` preserves TinyDB's insertion ordering.
  All query conditions are maps of field => value; a document matches when
  every listed field equals the given value, translated to per-field JSONB
  equality (`data -> field = value`) so semantics match an in-memory map
  exactly, including nested values and arrays.

  Mutations take a per-table PostgreSQL advisory transaction lock, so id
  assignment and check-and-insert are race-free without serializing
  unrelated tables through one process. A function passed to
  `transaction/1` runs all enclosed operations in one database
  transaction: either everything commits or nothing is visible.

  The database is the acknowledgement boundary: if a write cannot be
  committed the caller gets an error, never a false success.
  """

  import Ecto.Query

  alias BaconNet.DB.Document
  alias BaconNet.Repo

  @doc "First document in `table` matching all conditions, or nil."
  def get(table, conds) when is_map(conds) do
    table |> matching(conds) |> limit(1) |> select([d], d.data) |> Repo.one()
  end

  @doc "All documents in `table` matching all conditions."
  def search(table, conds) when is_map(conds) do
    table |> matching(conds) |> select([d], d.data) |> Repo.all()
  end

  @doc "All documents in `table`."
  def all(table), do: search(table, %{})

  @doc "All documents in `table` matching all conditions, as {doc_id, doc} pairs."
  def search_with_ids(table, conds) when is_map(conds) do
    table |> matching(conds) |> select([d], {d.doc_id, d.data}) |> Repo.all()
  end

  @doc "All documents in `table`, as {doc_id, doc} pairs."
  def all_with_ids(table), do: search_with_ids(table, %{})

  @doc "Document in `table` with the given doc id, or nil."
  def get_by_id(table, id) do
    Repo.one(
      from(d in Document,
        where: d.table_name == ^table and d.doc_id == ^to_string(id),
        select: d.data
      )
    )
  end

  @doc "Insert a document. Returns {doc_id, doc}."
  def insert_with_id(table, doc) when is_map(doc) do
    with_table_lock(table, fn ->
      id = Integer.to_string(next_id(table))
      insert_row!(table, id, doc)
      {id, doc}
    end)
  end

  @doc "Replace the document with the given doc id entirely. Returns :ok or :not_found."
  def replace_by_id(table, id, doc) when is_map(doc) do
    {count, _} =
      table
      |> by_id(id)
      |> Repo.update_all(set: [data: doc])

    if count == 0, do: :not_found, else: :ok
  end

  @doc "Merge `fields` into the document with the given doc id. Returns :ok or :not_found."
  def update_by_id(table, id, fields) when is_map(fields) do
    {count, _} =
      table
      |> by_id(id)
      |> merge_update(fields)
      |> Repo.update_all([])

    if count == 0, do: :not_found, else: :ok
  end

  @doc "Remove the document with the given doc id. Returns :ok or :not_found."
  def remove_by_id(table, id) do
    {count, _} = table |> by_id(id) |> Repo.delete_all()
    if count == 0, do: :not_found, else: :ok
  end

  @doc "All table names with their document counts, sorted by name."
  def tables do
    Repo.all(from(d in Document, group_by: d.table_name, select: {d.table_name, count()}))
    |> Enum.sort()
  end

  @doc "Drop an entire table."
  def drop_table(table) do
    Repo.delete_all(from(d in Document, where: d.table_name == ^table))
    :ok
  end

  @doc "Insert a document. Returns the document."
  def insert(table, doc) when is_map(doc) do
    {_id, doc} = insert_with_id(table, doc)
    doc
  end

  @doc "Merge `fields` into every document of `table` matching `conds`."
  def update(table, fields, conds) when is_map(fields) and is_map(conds) do
    table
    |> matching(conds)
    |> exclude(:order_by)
    |> merge_update(fields)
    |> Repo.update_all([])

    :ok
  end

  @doc "Merge `doc` into every document matching `conds`; insert `doc` when none match."
  def upsert(table, doc, conds) when is_map(doc) and is_map(conds) do
    with_table_lock(table, fn ->
      if Repo.exists?(matching(table, conds)) do
        table |> matching(conds) |> exclude(:order_by) |> merge_update(doc) |> Repo.update_all([])
        :ok
      else
        id = Integer.to_string(next_id(table))
        insert_row!(table, id, doc)
        doc
      end
    end)
  end

  @doc "Remove every document of `table` matching `conds`."
  def remove(table, conds) when is_map(conds) do
    table |> matching(conds) |> exclude(:order_by) |> Repo.delete_all()
    :ok
  end

  @doc """
  Insert `doc` unless a document matching `conds` already exists, as a single
  atomic check-and-insert. Returns :inserted or :exists.
  """
  def insert_unless_exists(table, doc, conds) when is_map(doc) and is_map(conds) do
    with_table_lock(table, fn ->
      if Repo.exists?(matching(table, conds)) do
        :exists
      else
        id = Integer.to_string(next_id(table))
        insert_row!(table, id, doc)
        :inserted
      end
    end)
  end

  @doc """
  Run `fun` inside one database transaction. All enclosed DB operations
  commit together; if `fun` raises or the transaction rolls back, nothing
  is visible. Returns `{:ok, result}` or `{:error, reason}`.
  """
  def transaction(fun), do: Repo.transaction(fun)

  @doc "Roll back the enclosing `transaction/1` with `reason`."
  def rollback(reason), do: Repo.rollback(reason)

  ## Internals

  defp by_id(table, id) do
    from(d in Document, where: d.table_name == ^table and d.doc_id == ^to_string(id))
  end

  defp merge_update(query, fields) do
    from(d in query,
      update: [set: [data: fragment("? || ?::text::jsonb", d.data, ^Jason.encode!(fields))]]
    )
  end

  # Per-key exact JSONB equality matches Elixir map semantics: object key
  # order is irrelevant on both sides, arrays compare in order, and a
  # nested map must be equal rather than merely contained (unlike @>).
  # A nil condition value matches documents where the key is absent or null.
  defp matching(table, conds) do
    Enum.reduce(conds, from(d in base(table), order_by: [asc: d.seq]), fn
      {key, nil}, query ->
        from(d in query,
          where:
            fragment(
              "NOT jsonb_exists(?, ?) OR ?->? = 'null'::jsonb",
              d.data,
              ^key,
              d.data,
              ^key
            )
        )

      {key, value}, query ->
        from(d in query,
          where: fragment("?->? = ?::text::jsonb", d.data, ^key, ^Jason.encode!(value))
        )
    end)
  end

  defp base(table), do: from(d in Document, where: d.table_name == ^table)

  defp next_id(table) do
    %{rows: [[id]]} =
      Repo.query!(
        """
        SELECT COALESCE(MAX(d.doc_id::bigint), 0) + 1
        FROM documents d
        WHERE d.table_name = $1 AND d.doc_id ~ '^[0-9]{1,18}$'
        """,
        [table]
      )

    id
  end

  defp insert_row!(table, id, doc) do
    Repo.insert!(%Document{table_name: table, doc_id: id, data: doc})
  end

  # Serializes writers of one table for the duration of the surrounding
  # transaction, so id assignment and check-and-insert cannot interleave.
  defp with_table_lock(table, fun) do
    {:ok, result} =
      Repo.transaction(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [table])
        fun.()
      end)

    result
  end
end
