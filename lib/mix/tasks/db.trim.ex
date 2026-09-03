defmodule Mix.Tasks.Db.Trim do
  @moduledoc """
  Trim unused non-best score tables from the database.

      mix db.trim
  """

  use Mix.Task

  alias BaconNet.DB

  @shortdoc "Drop unused tables from the database"

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    # Non-best tables for GITADORA and IIDX are not used in game
    for table <- ["guitarfreaks_scores", "drummania_scores", "iidx_scores"] do
      DB.drop_table(table)
      IO.puts("Dropped #{table}")
    end
  end
end
