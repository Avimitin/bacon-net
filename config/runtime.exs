import Config

if config_env() == :prod do
  # Production never bootstraps a local cluster and never migrates on boot;
  # run `bin/bacon_net eval "BaconNet.Release.migrate()"` explicitly.
  config :bacon_net,
    database_url: System.fetch_env!("DATABASE_URL"),
    migrate_on_start: false

  config :bacon_net, BaconNet.Repo,
    pool_size: String.to_integer(System.get_env("BACON_DB_POOL_SIZE", "10"))

  # Optional environment overrides for the application defaults.
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

  if admin_token = System.get_env("BACON_ADMIN_TOKEN") do
    config :bacon_net, admin_token: admin_token
  end

  if public_url = System.get_env("BACON_PUBLIC_URL") do
    config :bacon_net, public_url: public_url
  end

  if max_decompressed = System.get_env("BACON_MAX_DECOMPRESSED_BODY") do
    config :bacon_net, max_decompressed_body: String.to_integer(max_decompressed)
  end

  if origins = System.get_env("BACON_CORS_ORIGINS") do
    config :bacon_net, cors_origins: String.split(origins, ",", trim: true)
  end

  if System.get_env("BACON_LEGACY_GAME_APIS") == "1" do
    config :bacon_net, enable_legacy_game_apis: true
  end
end
