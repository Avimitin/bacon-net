defmodule BaconNet.MixProject do
  use Mix.Project

  def project do
    [
      app: :bacon_net,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
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

  defp aliases do
    [compile: [&generate_cp932/1, "compile"]]
  end

  # Generate the codec table as an ignored build artifact. Mix symlinks priv/
  # into development builds and copies it into releases.
  defp generate_cp932(_args) do
    source = Path.join(__DIR__, "scripts/gen_cp932.py")
    target = Path.join([__DIR__, "priv", "cp932.bin"])

    if stale?(source, target) do
      python =
        System.find_executable("python3") ||
          Mix.raise("python3 is required to generate cp932.bin")

      File.mkdir_p!(Path.dirname(target))
      {output, status} = System.cmd(python, [source, target], stderr_to_stdout: true)

      if status != 0 do
        Mix.raise("failed to generate cp932.bin:\n#{output}")
      end

      Mix.shell().info(String.trim(output))
    end
  end

  defp stale?(source, target) do
    with {:ok, source_stat} <- File.stat(source, time: :posix),
         {:ok, target_stat} <- File.stat(target, time: :posix) do
      source_stat.mtime > target_stat.mtime
    else
      _ -> true
    end
  end

  defp releases do
    [
      bacon_net: [
        include_executables_for: [:unix],
        applications: [bacon_net: :permanent]
      ]
    ]
  end
end
