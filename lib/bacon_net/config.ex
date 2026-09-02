defmodule BaconNet.Config do
  @moduledoc """
  Server configuration (config.py counterpart).

  Values come from Application env (see config/config.exs, overridable via
  environment variables in config/runtime.exs) with the same defaults as
  the Python config.
  """

  @default_arcade "Ｍ０ＮＫＹＢＵＳ１Ｎ３Ｚ"

  def ip do
    Application.get_env(:bacon_net, :ip) || detect_ip()
  end

  @doc "Bearer token protecting /manage/api; nil means open (development default)."
  def admin_token, do: Application.get_env(:bacon_net, :admin_token)

  @doc "Directory the static webui is served from (priv/static unless overridden)."
  def webui_dir do
    Application.get_env(:bacon_net, :webui_dir) ||
      Path.join(:code.priv_dir(:bacon_net) |> to_string(), "static")
  end

  def port, do: Application.get_env(:bacon_net, :port, 8000)
  def response_compression, do: Application.get_env(:bacon_net, :response_compression, false)
  def verbose_log, do: Application.get_env(:bacon_net, :verbose_log, true)
  def arcade, do: Application.get_env(:bacon_net, :arcade, @default_arcade)
  def paseli, do: Application.get_env(:bacon_net, :paseli, 10_000)
  def maintenance_mode, do: Application.get_env(:bacon_net, :maintenance_mode, false)

  @doc "Settings map exposed at /config."
  def settings do
    %{
      "ip" => ip(),
      "port" => port(),
      "response_compression" => response_compression(),
      "verbose_log" => verbose_log(),
      "arcade" => arcade(),
      "paseli" => paseli(),
      "maintenance_mode" => maintenance_mode()
    }
  end

  # UDP socket trick from config.py: no traffic is actually sent.
  defp detect_ip do
    case :gen_udp.open(0) do
      {:ok, sock} ->
        :gen_udp.connect(sock, {10, 254, 254, 254}, 1)

        addr =
          case :inet.sockname(sock) do
            {:ok, {ip, _port}} -> ip
            _ -> {127, 0, 0, 1}
          end

        :gen_udp.close(sock)
        addr |> :inet.ntoa() |> to_string()

      _ ->
        "127.0.0.1"
    end
  end
end
