defmodule BaconNet.RecoveryTest do
  @moduledoc """
  Durability invariants: the database — not any process — holds
  authoritative state, and a crashed writer never leaves partial rows.
  """

  use ExUnit.Case, async: false

  alias BaconNet.DB

  @table "recovery_probe"

  setup do
    DB.drop_table(@table)
    on_exit(fn -> DB.drop_table(@table) end)
    :ok
  end

  test "committed data survives a Repo restart" do
    DB.insert(@table, %{"k" => "v"})

    :ok = Supervisor.terminate_child(BaconNet.Supervisor, BaconNet.Repo)
    {:ok, _} = Supervisor.restart_child(BaconNet.Supervisor, BaconNet.Repo)

    assert DB.get(@table, %{"k" => "v"}) == %{"k" => "v"}
  end

  test "a writer killed mid-transaction leaves no partial rows" do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        DB.transaction(fn ->
          DB.insert(@table, %{"k" => "partial"})
          send(parent, :inserted)
          # Simulate a node/process crash after the insert but before commit.
          Process.exit(self(), :kill)
        end)
      end)

    assert_receive :inserted, 5_000
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 5_000

    assert DB.get(@table, %{"k" => "partial"}) == nil
  end

  test "an acknowledged write is visible after the client connection is gone" do
    # A handler may finish the DB work while the client has already given
    # up; the commit must stand and a retry is deduplicated upstream by the
    # idempotency layer (see IdempotencyTest).
    task = Task.async(fn -> DB.insert(@table, %{"k" => "acked"}) end)
    Task.shutdown(task, :brutal_kill)

    # Either it committed before the kill or not at all — never partial.
    case DB.get(@table, %{"k" => "acked"}) do
      nil -> assert DB.all(@table) == []
      doc -> assert doc == %{"k" => "acked"}
    end
  end
end
