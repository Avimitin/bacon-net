defmodule BaconNet.MixProject do
  use Mix.Project

  def project do
    [
      app: :bacon_net,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :xmerl],
      mod: {BaconNet.Application, []}
    ]
  end

  defp deps do
    [
      {:bandit, "~> 1.5"},
      {:jason, "~> 1.4"}
    ]
  end

  defp releases do
    [
      bacon_net: [
        include_executables_for: [:unix],
        applications: [bacon_net: :permanent],
        cookie: "bacon_net"
      ]
    ]
  end
end
