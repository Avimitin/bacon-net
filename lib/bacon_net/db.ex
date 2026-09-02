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

  @doc "Path of the backing JSON file."
  def path do
    Application.get_env(:bacon_net, :db_path, "db.json")
  end

  ## Server

  @impl true
  def init(_opts) do
    data =
      case File.read(path()) do
        {:ok, json} -> Jason.decode!(json)
        {:error, _} -> %{}
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

  ## Internals

  # TinyDB iterates documents in insertion order, which matches ascending
  # numeric document ids.
  defp sorted_docs(docs) do
    docs
    |> Enum.sort_by(fn {id, _doc} ->
      case Integer.parse(id) do
        {n, _} -> n
        :error -> 0
      end
    end)
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

  defp persist(data) do
    File.write(path(), Jason.encode!(data, pretty: true))
  end
end
