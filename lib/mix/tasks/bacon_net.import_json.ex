defmodule Mix.Tasks.BaconNet.ImportJson do
  @moduledoc """
  Import a TinyDB-format db.json (MonkeyBusiness layout) into PostgreSQL.

      mix bacon_net.import_json [db.json]

  Document ids and insertion order are preserved. Existing rows with the
  same {table, id} are skipped, so the import is safe to re-run; reconcile
  counts against the source before cutting over.
  """

  use Mix.Task

  alias BaconNet.DB.Document
  alias BaconNet.Repo

  @shortdoc "Import a TinyDB db.json into PostgreSQL"

  @impl true
  def run(args) do
    infile = List.first(args) || "db.json"

    Mix.Task.run("app.start")

    data =
      case File.read(infile) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, data} when is_map(data) -> data
            _ -> Mix.raise("failed to load #{infile}: malformed JSON")
          end

        {:error, reason} ->
          Mix.raise("failed to read #{infile}: #{:file.format_error(reason)}")
      end

    for {table, docs} <- data do
      rows =
        docs
        |> Enum.sort_by(fn {id, _doc} ->
          case Integer.parse(id) do
            {n, _} -> n
            :error -> 0
          end
        end)
        |> Enum.map(fn {id, doc} ->
          %{table_name: table, doc_id: id, data: doc}
        end)

      {count, _} =
        Repo.insert_all(
          Document,
          rows,
          on_conflict: :nothing,
          conflict_target: [:table_name, :doc_id]
        )

      Mix.shell().info("#{table}: imported #{count}/#{map_size(docs)} documents")
    end
  end
end
