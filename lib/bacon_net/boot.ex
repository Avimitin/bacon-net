defmodule BaconNet.Boot do
  @moduledoc """
  Startup banner and local endpoint summary.
  """

  alias BaconNet.Config

  @source_repository "https://github.com/Avimitin/bacon-net"

  def announce do
    if Application.get_env(:bacon_net, :announce_boot, true) do
      IO.puts("")
      IO.puts(IO.ANSI.bright() <> "bacon-net" <> IO.ANSI.reset())
      IO.puts("")
      IO.puts(IO.ANSI.bright() <> "Game Config" <> IO.ANSI.reset() <> ":")

      for url <- server_services_urls() do
        IO.puts("<services>" <> IO.ANSI.green() <> url <> IO.ANSI.reset() <> "</services>")
      end

      IO.puts(
        "<!-- url_slash " <>
          IO.ANSI.green() <>
          "0" <> IO.ANSI.reset() <> " or " <> IO.ANSI.green() <> "1" <> IO.ANSI.reset() <> " -->"
      )

      IO.puts("")
      IO.puts(IO.ANSI.bright() <> "Web Interface" <> IO.ANSI.reset() <> ":")

      if webui?() do
        for address <- server_addresses() do
          IO.puts("http://#{address}/webui/")
        end
      else
        IO.puts("webui not found in #{Config.webui_dir()}")
        IO.puts("build it with `nix build` (bundled) or see frontend/README.md")
      end

      IO.puts("")
      IO.puts(IO.ANSI.bright() <> "Source Repository" <> IO.ANSI.reset() <> ":")
      IO.puts(@source_repository)
      IO.puts("")
    end
  end

  def server_addresses do
    hosts = ["localhost", Config.ip()]
    hosts = if node_host = hostname(), do: hosts ++ [node_host], else: hosts

    for host <- hosts, do: "#{host}:#{Config.port()}"
  end

  def server_services_urls do
    for address <- server_addresses(), do: "http://#{address}/core"
  end

  def webui?, do: File.exists?(Path.join(Config.webui_dir(), "index.html"))

  defp hostname do
    case :inet.gethostname() do
      {:ok, name} -> to_string(name)
      _ -> nil
    end
  end
end
