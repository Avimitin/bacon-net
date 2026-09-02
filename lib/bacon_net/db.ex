defmodule BaconNet.DB do
  @moduledoc """
  TinyDB-compatible JSON document store (core_database.py counterpart).

  Data lives in a `db.json` file in the working directory with the same
  layout TinyDB uses: `%{"table" => %{"1" => doc, "2" => doc}}`. Every
  mutation rewrites the file, mirroring TinyDB's write-through behaviour.

  All query conditions are maps of field => value; a document matches when
  every listed field equals the given value (TinyDB's `&`-of-`==` pattern).
  Documents are plain maps with string keys.
  """

  use GenServer

  require Logger

  ## Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "First document in `table` matching all conditions, or nil."
  def get(table, conds) when is_map(conds), do: GenServer.call(__MODULE__, {:get, table, conds})

  @doc "All documents in `table` matching all conditions."
  def search(table, conds) when is_map(conds),
    do: GenServer.call(__MODULE__, {:search, table, conds})

  @doc "All documents in `table`."
  def all(table), do: GenServer.call(__MODULE__, {:all, table})

  @doc "All documents in `table` matching all conditions, as {doc_id, doc} pairs."
  def search_with_ids(table, conds) when is_map(conds),
    do: GenServer.call(__MODULE__, {:search_with_ids, table, conds})

  @doc "All documents in `table`, as {doc_id, doc} pairs."
  def all_with_ids(table), do: GenServer.call(__MODULE__, {:all_with_ids, table})

  @doc "Document in `table` with the given doc id, or nil."
  def get_by_id(table, id), do: GenServer.call(__MODULE__, {:get_by_id, table, id})

  @doc "Insert a document. Returns {doc_id, doc}."
  def insert_with_id(table, doc) when is_map(doc),
    do: GenServer.call(__MODULE__, {:insert_with_id, table, doc})

  @doc "Replace the document with the given doc id entirely. Returns :ok or :not_found."
  def replace_by_id(table, id, doc) when is_map(doc),
    do: GenServer.call(__MODULE__, {:replace_by_id, table, id, doc})

  @doc "Merge `fields` into the document with the given doc id. Returns :ok or :not_found."
  def update_by_id(table, id, fields) when is_map(fields),
    do: GenServer.call(__MODULE__, {:update_by_id, table, id, fields})

  @doc "Remove the document with the given doc id. Returns :ok or :not_found."
  def remove_by_id(table, id), do: GenServer.call(__MODULE__, {:remove_by_id, table, id})

  @doc "All table names with their document counts, sorted by name."
  def tables, do: GenServer.call(__MODULE__, :tables)

  @doc "Drop an entire table."
  def drop_table(table), do: GenServer.call(__MODULE__, {:drop_table, table})

  @doc "Insert a document. Returns the document."
  def insert(table, doc) when is_map(doc), do: GenServer.call(__MODULE__, {:insert, table, doc})

  @doc "Merge `fields` into every document of `table` matching `conds`."
  def update(table, fields, conds) when is_map(fields) and is_map(conds),
    do: GenServer.call(__MODULE__, {:update, table, fields, conds})

  @doc "Merge `doc` into every document matching `conds`; insert `doc` when none match."
  def upsert(table, doc, conds) when is_map(doc) and is_map(conds),
    do: GenServer.call(__MODULE__, {:upsert, table, doc, conds})

  @doc "Remove every document of `table` matching `conds`."
  def remove(table, conds) when is_map(conds),
    do: GenServer.call(__MODULE__, {:remove, table, conds})

  @doc """
  Insert `doc` unless a document matching `conds` already exists, as a single
  atomic check-and-insert. Returns :inserted or :exists.
  """
  def insert_unless_exists(table, doc, conds) when is_map(doc) and is_map(conds),
    do: GenServer.call(__MODULE__, {:insert_unless_exists, table, doc, conds})

  @doc "Path of the backing JSON file."
  def path do
    Application.get_env(:bacon_net, :db_path, "db.json")
  end

  ## Server

  @impl true
  def init(_opts) do
    data =
      case File.read(path()) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, data} when is_map(data) ->
              data

            _ ->
              raise "failed to load database from #{path()}: malformed JSON"
          end

        {:error, :enoent} ->
          %{}

        {:error, reason} ->
          raise "failed to read database file #{path()}: #{:file.format_error(reason)}"
      end

    {:ok, data}
  end

  @impl true
  def handle_call({:get, table, conds}, _from, data) do
    result =
      data
      |> Map.get(table, %{})
      |> sorted_docs()
      |> Enum.find(&matches?(&1, conds))

    {:reply, result, data}
  end

  def handle_call({:search, table, conds}, _from, data) do
    result =
      data
      |> Map.get(table, %{})
      |> sorted_docs()
      |> Enum.filter(&matches?(&1, conds))

    {:reply, result, data}
  end

  def handle_call({:all, table}, _from, data) do
    {:reply, data |> Map.get(table, %{}) |> sorted_docs(), data}
  end

  def handle_call({:search_with_ids, table, conds}, _from, data) do
    result =
      data
      |> Map.get(table, %{})
      |> sorted_pairs()
      |> Enum.filter(fn {_id, d} -> matches?(d, conds) end)

    {:reply, result, data}
  end

  def handle_call({:all_with_ids, table}, _from, data) do
    {:reply, data |> Map.get(table, %{}) |> sorted_pairs(), data}
  end

  def handle_call({:get_by_id, table, id}, _from, data) do
    {:reply, get_in(data, [table, id]), data}
  end

  def handle_call({:insert_with_id, table, doc}, _from, data) do
    docs = Map.get(data, table, %{})
    id = next_id(docs)
    data = put_in(data, [Access.key(table, %{}), Integer.to_string(id)], doc)
    persist(data)
    {:reply, {Integer.to_string(id), doc}, data}
  end

  def handle_call({:replace_by_id, table, id, doc}, _from, data) do
    if get_in(data, [table, id]) do
      data = put_in(data, [table, id], doc)
      persist(data)
      {:reply, :ok, data}
    else
      {:reply, :not_found, data}
    end
  end

  def handle_call({:update_by_id, table, id, fields}, _from, data) do
    case get_in(data, [table, id]) do
      nil ->
        {:reply, :not_found, data}

      existing ->
        data = put_in(data, [table, id], Map.merge(existing, fields))
        persist(data)
        {:reply, :ok, data}
    end
  end

  def handle_call({:remove_by_id, table, id}, _from, data) do
    if get_in(data, [table, id]) do
      data = update_in(data, [table], &Map.delete(&1, id))
      persist(data)
      {:reply, :ok, data}
    else
      {:reply, :not_found, data}
    end
  end

  def handle_call(:tables, _from, data) do
    tables =
      data
      |> Enum.map(fn {table, docs} -> {table, map_size(docs)} end)
      |> Enum.sort()

    {:reply, tables, data}
  end

  def handle_call({:drop_table, table}, _from, data) do
    data = Map.delete(data, table)
    persist(data)
    {:reply, :ok, data}
  end

  def handle_call({:insert, table, doc}, _from, data) do
    docs = Map.get(data, table, %{})
    id = next_id(docs)
    data = put_in(data, [Access.key(table, %{}), Integer.to_string(id)], doc)
    persist(data)
    {:reply, doc, data}
  end

  def handle_call({:update, table, fields, conds}, _from, data) do
    docs = Map.get(data, table, %{})

    docs =
      Map.new(docs, fn {id, doc} ->
        if matches?(doc, conds), do: {id, Map.merge(doc, fields)}, else: {id, doc}
      end)

    data = Map.put(data, table, docs)
    persist(data)
    {:reply, :ok, data}
  end

  def handle_call({:upsert, table, doc, conds}, _from, data) do
    docs = Map.get(data, table, %{})

    if Enum.any?(docs, fn {_id, d} -> matches?(d, conds) end) do
      docs =
        Map.new(docs, fn {id, d} ->
          if matches?(d, conds), do: {id, Map.merge(d, doc)}, else: {id, d}
        end)

      data = Map.put(data, table, docs)
      persist(data)
      {:reply, :ok, data}
    else
      id = next_id(docs)
      data = put_in(data, [Access.key(table, %{}), Integer.to_string(id)], doc)
      persist(data)
      {:reply, doc, data}
    end
  end

  def handle_call({:remove, table, conds}, _from, data) do
    docs =
      data
      |> Map.get(table, %{})
      |> Enum.reject(fn {_id, d} -> matches?(d, conds) end)
      |> Map.new()

    data = Map.put(data, table, docs)
    persist(data)
    {:reply, :ok, data}
  end

  def handle_call({:insert_unless_exists, table, doc, conds}, _from, data) do
    docs = Map.get(data, table, %{})

    if Enum.any?(docs, fn {_id, d} -> matches?(d, conds) end) do
      {:reply, :exists, data}
    else
      id = next_id(docs)
      data = put_in(data, [Access.key(table, %{}), Integer.to_string(id)], doc)
      persist(data)
      {:reply, :inserted, data}
    end
  end

  ## Internals

  # TinyDB iterates documents in insertion order, which matches ascending
  # numeric document ids.
  defp sorted_pairs(docs) do
    Enum.sort_by(docs, fn {id, _doc} ->
      case Integer.parse(id) do
        {n, _} -> n
        :error -> 0
      end
    end)
  end

  defp sorted_docs(docs) do
    docs
    |> sorted_pairs()
    |> Enum.map(fn {_id, doc} -> doc end)
  end

  defp matches?(doc, conds) do
    Enum.all?(conds, fn {k, v} -> Map.get(doc, k) == v end)
  end

  defp next_id(docs) do
    docs
    |> Map.keys()
    |> Enum.map(fn k ->
      case Integer.parse(k) do
        {n, _} -> n
        :error -> 0
      end
    end)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  # Write-then-rename so a crash mid-write never leaves a truncated file;
  # a failed write raises so callers get an error instead of a false success
  # and the supervisor restarts us onto the last good file.
  defp persist(data) do
    target = path()
    tmp = target <> ".tmp"

    with :ok <- File.write(tmp, Jason.encode!(data, pretty: true)),
         :ok <- File.rename(tmp, target) do
      :ok
    else
      {:error, reason} ->
        Logger.error("failed to persist database to #{target}: #{:file.format_error(reason)}")
        raise "failed to persist database to #{target}: #{:file.format_error(reason)}"
    end
  end
end
