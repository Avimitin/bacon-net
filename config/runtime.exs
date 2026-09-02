import Config

if config_env() == :prod do
  # Optional environment overrides (all default to config.py values).
  if port = System.get_env("BACON_PORT") do
    config :bacon_net, port: String.to_integer(port)
  end

  if ip = System.get_env("BACON_IP") do
    config :bacon_net, ip: ip
  end

  if arcade = System.get_env("BACON_ARCADE") do
    config :bacon_net, arcade: arcade
  end

  if System.get_env("BACON_VERBOSE_LOG") == "0" do
    config :bacon_net, verbose_log: false
  end

  if System.get_env("BACON_RESPONSE_COMPRESSION") == "1" do
    config :bacon_net, response_compression: true
  end

  if System.get_env("BACON_MAINTENANCE_MODE") == "1" do
    config :bacon_net, maintenance_mode: true
  end

  if paseli = System.get_env("BACON_PASELI") do
    config :bacon_net, paseli: String.to_integer(paseli)
  end

  if webui_dir = System.get_env("BACON_WEBUI_DIR") do
    config :bacon_net, webui_dir: webui_dir
  end
end
