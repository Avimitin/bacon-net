defmodule BaconNet.Config do
  @moduledoc """
  Runtime configuration for the game protocol, web interface, and operations.

  Values come from the application environment (see `config/config.exs`) and
  can be overridden through `config/runtime.exs` in releases.
  """

  @default_arcade "ＢＡＣＯＮ－ＮＥＴ"

  def ip do
    Application.get_env(:bacon_net, :ip) || detect_ip()
  end

  @doc "Bearer token protecting /manage/api; nil means the management API is closed."
  def admin_token, do: Application.get_env(:bacon_net, :admin_token)

  @doc "Directory the static webui is served from (priv/static unless overridden)."
  def webui_dir do
    Application.get_env(:bacon_net, :webui_dir) ||
      Path.join(:code.priv_dir(:bacon_net) |> to_string(), "static")
  end

  def port, do: Application.get_env(:bacon_net, :port, 8000)

  @doc """
  Canonical base URL advertised to cabinets in services.get. Never derived
  from the request Host header. Defaults to http on the configured ip/port;
  set BACON_PUBLIC_URL in production (e.g. the TLS gateway URL).
  """
  def public_url do
    Application.get_env(:bacon_net, :public_url) || "http://#{ip()}:#{port()}"
  end

  def response_compression, do: Application.get_env(:bacon_net, :response_compression, false)
  def verbose_log, do: Application.get_env(:bacon_net, :verbose_log, true)
  def arcade, do: Application.get_env(:bacon_net, :arcade, @default_arcade)
  def paseli, do: Application.get_env(:bacon_net, :paseli, 10_000)
  def maintenance_mode, do: Application.get_env(:bacon_net, :maintenance_mode, false)

  @doc """
  Readiness probe run by GET /readyz: a zero-arity fun returning {:ok, _}
  when the server can reach its database. Overridable via Application env
  (used by tests to exercise the 503 path).
  """
  def readiness_check do
    Application.get_env(:bacon_net, :readiness_check) ||
      fn -> BaconNet.Repo.query("SELECT 1") end
  end

  def max_decompressed_body,
    do: Application.get_env(:bacon_net, :max_decompressed_body, 16_000_000)

  def cors_origins, do: Application.get_env(:bacon_net, :cors_origins, [])

  @doc "Legacy unauthenticated per-game JSON APIs (/iidx, /ddr, /gfdm); disabled by default."
  def legacy_game_apis, do: Application.get_env(:bacon_net, :enable_legacy_game_apis, false)

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

  # UDP socket discovery: no traffic is actually sent.
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
