import Config

config :bacon_net,
  port: 8000,
  response_compression: false,
  verbose_log: true,
  arcade: "Ｍ０ＮＫＹＢＵＳ１Ｎ３Ｚ",
  paseli: 10_000,
  maintenance_mode: false,
  max_decompressed_body: 16_000_000,
  cors_origins: [],
  enable_legacy_game_apis: false,
  ecto_repos: [BaconNet.Repo],
  migrate_on_start: true

config :bacon_net, BaconNet.Repo,
  local_cluster: true,
  env: :dev,
  port: 55_432,
  database: "bacon_net_dev"

config :logger, level: :info

if File.exists?(Path.expand("#{config_env()}.exs", __DIR__)) do
  import_config "#{config_env()}.exs"
end
