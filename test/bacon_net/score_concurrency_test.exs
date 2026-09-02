defmodule BaconNet.ScoreConcurrencyTest do
  use ExUnit.Case, async: false

  alias BaconNet.{DB, Repo, Scores}
  alias BaconNet.Scores.{BestScore, IdempotencyKey, Merge, OutboxEvent, PlayAttempt, ScoreStat}

  setup do
    cleanup()
    on_exit(&cleanup/0)
    :ok
  end

  defp cleanup do
    Repo.delete_all(PlayAttempt)
    Repo.delete_all(BestScore)
    Repo.delete_all(ScoreStat)
    Repo.delete_all(IdempotencyKey)
    Repo.delete_all(OutboxEvent)
    Enum.each(["iidx_scores", "iidx_scores_best", "iidx_score_stats"], &DB.drop_table/1)
    :ok
  end

  defp event(i, key) do
    %{
      game: "iidx",
      version: 33,
      player: "2002",
      song: 3000,
      chart: 1,
      play_style: "0",
      score: 1000 + i,
      clear: rem(i, 8),
      miss: rem(i, 20),
      payload: %{
        "ghost" => "ghost-#{i}",
        "ghost_gauge" => "gauge-#{i}",
        "gauge_type" => 0,
        "game_version" => 33,
        "pid" => 13
      },
      attempt: %{"i" => i},
      stats: %{clear: rem(i, 2) == 0, fc: rem(i, 10) == 0},
      merge: Merge.spec("iidx"),
      idempotency: %{key: key, scope: "concurrency-test", payload_hash: "hash-#{key}"}
    }
  end

  # Start all tasks blocked on a shared barrier, release them at once. No
  # sleeps: every task signals readiness and parks on `receive` until the
  # parent broadcasts :go.
  defp run_concurrently(n, fun) do
    parent = self()

    tasks =
      for i <- 1..n do
        Task.async(fn ->
          send(parent, {:ready, self()})
          receive do: (:go -> fun.(i))
        end)
      end

    for _ <- 1..n, do: assert_receive({:ready, _pid}, 5000)
    Enum.each(tasks, &send(&1.pid, :go))
    Task.await_many(tasks, 60_000)
  end

  test "50 simultaneous unique submissions: no lost updates anywhere" do
    results = run_concurrently(50, fn i -> Scores.record_attempt(event(i, "k#{i}")) end)

    assert Enum.all?(results, &match?({:ok, %{status: :recorded}}, &1)),
           "expected all recorded, got: #{inspect(Enum.reject(results, &match?({:ok, _}, &1)))}"

    assert Repo.aggregate(PlayAttempt, :count) == 50
    assert Repo.aggregate(IdempotencyKey, :count) == 50
    assert Repo.aggregate(OutboxEvent, :count) == 50

    best = Scores.get_best("iidx", "2002", 3000, 1, "0")
    assert best.score == 1050
    assert best.clear == 7

    stats = Scores.get_stats("iidx", 3000, 1, "0")
    assert stats.play_count == 50
    assert stats.clear_count == 25
    assert stats.fc_count == 5
  end

  test "concurrent submissions across players sharing one chart keep stats exact" do
    results =
      run_concurrently(30, fn i ->
        Scores.record_attempt(%{
          event(i, "shared-#{i}")
          | player: "player-#{i}",
            payload: %{
              "ghost" => "g#{i}",
              "ghost_gauge" => "gg#{i}",
              "gauge_type" => 0,
              "game_version" => 33,
              "pid" => 13
            }
        })
      end)

    assert Enum.all?(results, &match?({:ok, %{status: :recorded}}, &1))

    assert Repo.aggregate(PlayAttempt, :count) == 30
    assert Repo.aggregate(BestScore, :count) == 30
    assert Scores.get_stats("iidx", 3000, 1, "0").play_count == 30
  end
end
