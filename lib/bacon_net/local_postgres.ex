defmodule BaconNet.LocalPostgres do
  @moduledoc """
  Bootstraps a throwaway local PostgreSQL cluster for development and tests.

  Used only when the repo is configured with `local_cluster: true` and no
  `DATABASE_URL` is set; production always connects to a managed database.
  The cluster lives under `/tmp/bacon-net-pg-<env>` (a world-traversable
  path so an unprivileged server process can reach it) and survives
  across `mix` invocations; stop it with `pg_ctl -D <dir> stop`.

  Requires `initdb` and `pg_ctl` on PATH (provided by the Nix dev shell).
  PostgreSQL refuses to run as root, so when the current user is root the
  server processes are run as the `nobody` user via `runuser`.
  """

  require Logger

  @doc """
  Ensure the cluster described by the repo `config` is initialized, running,
  and holds the configured database. Returns `{port, database}`.
  """
  def ensure_running!(config) do
    env = config[:env] || :dev
    port = config[:port] || default_port(env)
    database = config[:database] || "bacon_net_#{env}"
    dir = config[:data_dir] || "/tmp/bacon-net-pg-#{env}"
    sockdir = Path.join(dir, "sock")

    initdb = find_executable!("initdb")
    pg_ctl = find_executable!("pg_ctl")

    File.mkdir_p!(dir)
    chown_for_pg(dir)

    unless File.exists?(Path.join(dir, "PG_VERSION")) do
      Logger.info("initializing local PostgreSQL cluster in #{dir}")

      run!(initdb, [
        "-D",
        dir,
        "-U",
        "postgres",
        "-E",
        "UTF8",
        "--auth-local=trust",
        "--auth-host=trust",
        "--no-instructions",
        "--no-sync"
      ])
    end

    File.mkdir_p!(sockdir)
    chown_for_pg(sockdir)

    unless running?(pg_ctl, dir) do
      Logger.info("starting local PostgreSQL on 127.0.0.1:#{port}")

      fsync = if env == :test, do: "off", else: "on"

      run!(pg_ctl, [
        "-D",
        dir,
        "-l",
        Path.join(dir, "postgres.log"),
        "-w",
        "-o",
        "-p #{port} -k #{sockdir} -c listen_addresses=127.0.0.1 -c fsync=#{fsync}",
        "start"
      ])
    end

    create_database!(port, database)
    {port, database}
  end

  defp default_port(:test), do: 55_433
  defp default_port(_), do: 55_432

  defp running?(pg_ctl, dir) do
    match?({_, 0}, run(pg_ctl, ["-D", dir, "status"]))
  end

  defp create_database!(port, database) do
    unless database =~ ~r/^[a-zA-Z_][a-zA-Z0-9_]*$/ do
      raise "invalid local database name: #{inspect(database)}"
    end

    {:ok, conn} =
      Postgrex.start_link(
        hostname: "127.0.0.1",
        port: port,
        username: "postgres",
        database: "postgres"
      )

    try do
      %{rows: rows} =
        Postgrex.query!(conn, "SELECT 1 FROM pg_database WHERE datname = $1", [database])

      if rows == [] do
        Logger.info("creating local database #{database}")
        Postgrex.query!(conn, "CREATE DATABASE #{database}", [])
      end
    after
      GenServer.stop(conn)
    end
  end

  # PostgreSQL refuses root; hand the data dir to nobody and run the
  # server binaries through runuser when we are root.
  defp chown_for_pg(dir) do
    if root?() do
      {uid, gid} = nobody_ids()
      :ok = :file.change_owner(dir, uid, gid)
    end
  end

  defp run(cmd, args) do
    if root?() do
      System.cmd(find_executable!("runuser"), ["-u", "nobody", "--", cmd | args],
        stderr_to_stdout: true
      )
    else
      System.cmd(cmd, args, stderr_to_stdout: true)
    end
  end

  defp run!(cmd, args) do
    case run(cmd, args) do
      {_, 0} -> :ok
      {output, status} -> raise "#{cmd} #{Enum.join(args, " ")} failed (#{status}):\n#{output}"
    end
  end

  defp root? do
    {out, 0} = System.cmd("id", ["-u"])
    String.trim(out) == "0"
  end

  defp nobody_ids do
    {uid, 0} = System.cmd("id", ["-u", "nobody"])
    {gid, 0} = System.cmd("id", ["-g", "nobody"])
    {String.to_integer(String.trim(uid)), String.to_integer(String.trim(gid))}
  end

  defp find_executable!(name) do
    System.find_executable(name) ||
      raise "#{name} not found on PATH; enter the Nix dev shell (nix develop) " <>
              "or configure DATABASE_URL to use an external PostgreSQL"
  end
end
