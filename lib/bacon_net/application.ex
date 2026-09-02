defmodule BaconNet.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    BaconNet.Boot.announce()

    children =
      [
        BaconNet.State,
        BaconNet.Repo
      ] ++
        if Application.get_env(:bacon_net, :start_server, true) do
          [{Bandit, plug: BaconNet.Router, ip: {0, 0, 0, 0}, port: BaconNet.Config.port()}]
        else
          []
        end

    with {:ok, pid} <-
           Supervisor.start_link(children, strategy: :one_for_one, name: BaconNet.Supervisor) do
      migrate_on_start()
      {:ok, pid}
    end
  end

  # Dev/test convenience: the schema follows the code automatically.
  # Production sets migrate_on_start: false and runs BaconNet.Release.migrate/0.
  defp migrate_on_start do
    if Application.get_env(:bacon_net, :migrate_on_start, false) do
      Ecto.Migrator.run(
        BaconNet.Repo,
        Application.app_dir(:bacon_net, "priv/repo/migrations"),
        :up,
        all: true,
        log: :info
      )
    end
  end
end
