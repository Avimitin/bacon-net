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
        BaconNet.DB
      ] ++
        if Application.get_env(:bacon_net, :start_server, true) do
          [{Bandit, plug: BaconNet.Router, ip: {0, 0, 0, 0}, port: BaconNet.Config.port()}]
        else
          []
        end

    Supervisor.start_link(children, strategy: :one_for_one, name: BaconNet.Supervisor)
  end
end
