defmodule BaconNet.Boot do
  @moduledoc """
  Startup banner and webui setup (pyeamu.py __main__ counterpart).
  """

  alias BaconNet.Config

  @banner """
   █▄ ▄█ █▀█ █▄ █ █▄▀ ▀██ ▀▄▀
   █ ▀ █ █▄█ █ ▀█ █ █ ▄▄█  █

   ██▄ █ █ ▄▀▀ ▄█ █▄ █ ▀██ ▀█▀
   █▄█ ▀▄█ ▄██  █ █ ▀█ ▄▄█ █▄▄
  """

  def announce do
    setup_webui()

    if Application.get_env(:bacon_net, :announce_boot, true) do
      IO.puts("")
      IO.puts(@banner)
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
        IO.puts("/webui missing")
        IO.puts("download it here: https://github.com/drmext/BounceTrippy/releases")
      end

      IO.puts("")
      IO.puts(IO.ANSI.bright() <> "Source Repository" <> IO.ANSI.reset() <> ":")
      IO.puts("https://github.com/drmext/MonkeyBusiness")
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

  def webui?, do: File.dir?("webui")

  defp setup_webui do
    if webui?() do
      File.write(Path.join("webui", "monkey.json"), Jason.encode!(Config.settings(), pretty: true))
    end
  end

  defp hostname do
    case :inet.gethostname() do
      {:ok, name} -> to_string(name)
      _ -> nil
    end
  end
end
