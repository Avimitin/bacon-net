defmodule Mix.Tasks.Db.Trim do
  @moduledoc """
  Trim unused non-best score tables from db.json
  (utils/db/trim_monkey_db.py counterpart).

      mix db.trim [db.json]
  """

  use Mix.Task

  alias BaconNet.DB

  @shortdoc "Trim unused tables from db.json"

  @impl true
  def run(args) do
    infile = List.first(args) || "db.json"
    outfile = "db_#{:os.system_time(:second)}.json"

    File.cp!(infile, outfile)

    Application.put_env(:bacon_net, :db_path, infile)
    {:ok, _} = DB.start_link()

    start_size = File.stat!(infile).size

    # Non-best tables for GITADORA and IIDX are not used in game
    for table <- ["guitarfreaks_scores", "drummania_scores", "iidx_scores"] do
      DB.drop_table(table)
      IO.puts("Dropped #{table}")
    end

    end_size = File.stat!(infile).size

    IO.puts("#{infile} #{Float.round((start_size - end_size) / 1024 / 1024, 2)} MiB trimmed")
  end
end
