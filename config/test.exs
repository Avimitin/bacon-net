import Config

config :bacon_net,
  start_server: false,
  announce_boot: false,
  verbose_log: false

config :bacon_net, BaconNet.Repo,
  local_cluster: true,
  env: :test,
  port: 55_433,
  database: "bacon_net_test",
  pool_size: 10

config :logger, level: :warning
