defmodule BaconNet.Repo do
  @moduledoc """
  PostgreSQL repository. This is the acknowledgement boundary for every
  write: a command only reports success after the database commits.

  Connection comes from `DATABASE_URL` (production), or from a local
  throwaway cluster bootstrapped by `BaconNet.LocalPostgres` when
  `local_cluster: true` is configured (dev/test default).
  """

  use Ecto.Repo, otp_app: :bacon_net, adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_context, config) do
    config =
      cond do
        url = Application.get_env(:bacon_net, :database_url) ->
          config |> Keyword.delete(:local_cluster) |> Keyword.put(:url, url)

        config[:local_cluster] ->
          {port, database} = BaconNet.LocalPostgres.ensure_running!(config)

          config
          |> Keyword.delete(:local_cluster)
          |> Keyword.put(:hostname, "127.0.0.1")
          |> Keyword.put(:username, "postgres")
          |> Keyword.put(:port, port)
          |> Keyword.put(:database, database)

        true ->
          config
      end

    {:ok, config}
  end
end
