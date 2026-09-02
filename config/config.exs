import Config

config :bacon_net,
  port: 8000,
  response_compression: false,
  verbose_log: true,
  arcade: "Ｍ０ＮＫＹＢＵＳ１Ｎ３Ｚ",
  paseli: 10_000,
  maintenance_mode: false

config :logger, level: :info

if File.exists?(Path.expand("#{config_env()}.exs", __DIR__)) do
  import_config "#{config_env()}.exs"
end
