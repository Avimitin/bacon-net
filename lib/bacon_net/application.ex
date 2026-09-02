defmodule BaconNet.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BaconNet.DB
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: BaconNet.Supervisor)
  end
end
