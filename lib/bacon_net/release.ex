defmodule BaconNet.Release do
  @moduledoc """
  Release tasks. Production runs migrations explicitly:

      bin/bacon_net eval "BaconNet.Release.migrate()"

  before starting new application nodes (expand/migrate/contract).
  """

  @app :bacon_net

  def migrate do
    Application.load(@app)

    {:ok, _} = Application.ensure_all_started(:ssl)
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    {:ok, pid} = BaconNet.Repo.start_link(timeout: 15_000)

    try do
      Ecto.Migrator.run(
        BaconNet.Repo,
        Application.app_dir(@app, "priv/repo/migrations"),
        :up,
        all: true
      )
    after
      Supervisor.stop(pid)
    end
  end
end
