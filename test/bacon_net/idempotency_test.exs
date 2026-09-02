defmodule BaconNet.IdempotencyTest do
  use ExUnit.Case, async: false

  alias BaconNet.{Repo, Scores}
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
    :ok
  end

  defp event(key, payload_hash, overrides \\ %{}) do
    Map.merge(
      %{
        game: "iidx",
        version: 33,
        player: "3003",
        song: 4000,
        chart: 3,
        play_style: "1",
        score: 1400,
        clear: 5,
        miss: 2,
        payload: %{
          "ghost" => "aa",
          "ghost_gauge" => "bb",
          "gauge_type" => 0,
          "game_version" => 33,
          "pid" => 13
        },
        attempt: %{"note" => "same"},
        stats: %{clear: true, fc: false},
        merge: Merge.spec("iidx"),
        idempotency: %{key: key, scope: "idempotency-test", payload_hash: payload_hash}
      },
      overrides
    )
  end

  test "the same event submitted twice records once and replays the second time" do
    assert {:ok, first} = Scores.record_attempt(event("k1", "h1"))
    assert first.status == :recorded

    assert {:ok, second} = Scores.record_attempt(event("k1", "h1"))
    assert second.status == :replayed
    assert second.response == first.response

    assert Repo.aggregate(PlayAttempt, :count) == 1
    assert Repo.aggregate(OutboxEvent, :count) == 1
    assert Scores.get_stats("iidx", 4000, 3, "1").play_count == 1
    assert Repo.aggregate(IdempotencyKey, :count) == 1
  end

  test "simulated client timeout: first response lost, retry replays" do
    assert {:ok, first} = Scores.record_attempt(event("k2", "h2"))
    # the response never reaches the client; it retries byte-identically
    assert {:ok, retry} = Scores.record_attempt(event("k2", "h2"))

    assert retry.status == :replayed
    assert retry.response == first.response
    assert Repo.aggregate(PlayAttempt, :count) == 1
    assert Scores.get_stats("iidx", 4000, 3, "1").play_count == 1
  end

  test "concurrent identical submissions: exactly one records, the rest replay" do
    parent = self()

    tasks =
      for _ <- 1..10 do
        Task.async(fn ->
          send(parent, {:ready, self()})
          receive do: (:go -> Scores.record_attempt(event("k3", "h3")))
        end)
      end

    for _ <- 1..10, do: assert_receive({:ready, _pid}, 5000)
    Enum.each(tasks, &send(&1.pid, :go))
    results = Task.await_many(tasks, 60_000)

    recorded = Enum.filter(results, &match?({:ok, %{status: :recorded}}, &1))
    replayed = Enum.filter(results, &match?({:ok, %{status: :replayed}}, &1))

    assert length(recorded) == 1
    assert length(replayed) == 9

    [{:ok, first} | _] = recorded
    assert Enum.all?(replayed, fn {:ok, r} -> r.response == first.response end)

    assert Repo.aggregate(PlayAttempt, :count) == 1
    assert Repo.aggregate(OutboxEvent, :count) == 1
    assert Scores.get_stats("iidx", 4000, 3, "1").play_count == 1
  end

  test "two events identical except a nonce both commit" do
    assert {:ok, %{status: :recorded}} = Scores.record_attempt(event("nonce-a", "ha"))
    assert {:ok, %{status: :recorded}} = Scores.record_attempt(event("nonce-b", "hb"))

    assert Repo.aggregate(PlayAttempt, :count) == 2
    assert Scores.get_stats("iidx", 4000, 3, "1").play_count == 2
  end

  test "key reuse with a different payload is a conflict" do
    assert {:ok, %{status: :recorded, response: response}} =
             Scores.record_attempt(event("k4", "h4"))

    assert {:error, :idempotency_conflict} = Scores.record_attempt(event("k4", "DIFFERENT"))

    assert Repo.aggregate(PlayAttempt, :count) == 1
    assert Scores.get_stats("iidx", 4000, 3, "1").play_count == 1
    # the recorded outcome is untouched
    assert Repo.get_by!(IdempotencyKey, key: "k4").response == response
  end

  test "derived keys are stable for identical input and distinct otherwise" do
    body = "<call><IIDX33music method=\"reg\"/></call>"

    k1 = Scores.derive_key("iidx", "reg", 1001, body)
    assert k1 == Scores.derive_key("iidx", "reg", 1001, body)
    assert String.length(k1) == 64

    refute k1 == Scores.derive_key("iidx", "reg", 1002, body)
    refute k1 == Scores.derive_key("iidx", "reg", 1001, body <> " ")
    refute k1 == Scores.derive_key("ddr", "reg", 1001, body)
  end
end
