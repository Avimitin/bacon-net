defmodule BaconNet.Application do
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    BaconNet.Boot.announce()

    children = [
      BaconNet.State,
      BaconNet.DB,
      {Bandit, plug: BaconNet.Router, ip: {0, 0, 0, 0}, port: BaconNet.Config.port()}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: BaconNet.Supervisor)
  end
end
