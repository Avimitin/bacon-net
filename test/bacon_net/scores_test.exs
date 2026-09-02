defmodule BaconNet.ScoresTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias BaconNet.{DB, E, Kbinxml, Repo, Scores, Shop, XNode}
  alias BaconNet.Scores.{BestScore, IdempotencyKey, Merge, OutboxEvent, PlayAttempt, ScoreStat}

  @doc_tables [
    "iidx_scores",
    "iidx_scores_best",
    "iidx_score_stats",
    "ddr_scores",
    "ddr_scores_best",
    "guitarfreaks_scores",
    "guitarfreaks_scores_best",
    "drummania_scores",
    "drummania_scores_best"
  ]

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
    Enum.each(@doc_tables, &DB.drop_table/1)
    :ok
  end

  defp iidx_payload(overrides \\ %{}) do
    Map.merge(
      %{
        "ghost" => "aa00",
        "ghost_gauge" => "bb11",
        "gauge_type" => 0,
        "game_version" => 33,
        "pid" => 13
      },
      overrides
    )
  end

  defp iidx_event(overrides \\ %{}) do
    Map.merge(
      %{
        game: "iidx",
        version: 33,
        player: "1001",
        song: 2000,
        chart: 2,
        play_style: "0",
        score: 1500,
        clear: 4,
        miss: 3,
        payload: iidx_payload(),
        attempt: %{"raw" => "fields"},
        stats: %{clear: true, fc: false},
        merge: Merge.spec("iidx"),
        idempotency: %{
          key: "test-#{System.unique_integer([:positive])}",
          scope: "test",
          payload_hash: "hash"
        }
      },
      overrides
    )
  end

  test "one valid submission records exactly one attempt, best, stats, outbox" do
    assert {:ok, result} = Scores.record_attempt(iidx_event())
    assert result.status == :recorded

    assert Repo.aggregate(PlayAttempt, :count) == 1

    attempt = Repo.one!(PlayAttempt)
    assert attempt.game == "iidx"
    assert attempt.version == 33
    assert attempt.player == "1001"
    assert attempt.song == 2000
    assert attempt.chart == 2
    assert attempt.play_style == "0"
    assert attempt.score == 1500
    assert attempt.clear == 4
    assert attempt.miss == 3
    assert attempt.payload == %{"raw" => "fields"}
    assert attempt.created_at

    best = Scores.get_best("iidx", "1001", 2000, 2, "0")
    assert best.score == 1500
    assert best.clear == 4
    assert best.miss == 3
    assert best.payload["ghost"] == "aa00"

    stats = Scores.get_stats("iidx", 2000, 2, "0")
    assert stats.play_count == 1
    assert stats.clear_count == 1
    assert stats.fc_count == 0

    outbox = Repo.one!(OutboxEvent)
    assert outbox.topic == "score.recorded"
    assert outbox.payload["attempt_id"] == attempt.id
    assert outbox.payload["score"] == 1500
    assert outbox.published_at == nil

    key = Repo.one!(IdempotencyKey)
    assert key.response["attempt_id"] == attempt.id
    assert key.response["stats"]["play_count"] == 1
  end

  test "lower score never lowers best; clear improves; provenance follows the best score" do
    assert {:ok, _} = Scores.record_attempt(iidx_event())

    weaker =
      iidx_event(%{
        score: 1200,
        clear: 7,
        miss: 1,
        payload: iidx_payload(%{"ghost" => "zz99", "gauge_type" => 2, "pid" => 99})
      })

    assert {:ok, result} = Scores.record_attempt(weaker)
    assert result.status == :recorded

    best = Scores.get_best("iidx", "1001", 2000, 2, "0")
    # score does not regress; clear flag still improves; miss takes the min
    assert best.score == 1500
    assert best.clear == 7
    assert best.miss == 1
    # ghost/gauge stay with the higher-scoring play
    assert best.payload["ghost"] == "aa00"
    assert best.payload["gauge_type"] == 0
    # overwrite fields track the latest play
    assert best.payload["pid"] == 99

    assert Repo.aggregate(PlayAttempt, :count) == 2
    assert Scores.get_stats("iidx", 2000, 2, "0").play_count == 2
  end

  test "better score updates only its own provenance fields" do
    assert {:ok, _} = Scores.record_attempt(iidx_event(%{clear: 7, miss: 1}))

    stronger =
      iidx_event(%{
        score: 1800,
        clear: 3,
        miss: 9,
        payload: iidx_payload(%{"ghost" => "cc22", "gauge_type" => 1})
      })

    assert {:ok, _} = Scores.record_attempt(stronger)

    best = Scores.get_best("iidx", "1001", 2000, 2, "0")
    assert best.score == 1800
    # clear flag is monotonic on its own, not dragged down by the better score
    assert best.clear == 7
    assert best.miss == 1
    # provenance fields follow the new best score
    assert best.payload["ghost"] == "cc22"
    assert best.payload["gauge_type"] == 1
  end

  test "iidx miss rule: -1 means unknown and loses to any real count" do
    assert {:ok, _} = Scores.record_attempt(iidx_event(%{miss: -1}))
    assert {:ok, _} = Scores.record_attempt(iidx_event(%{miss: 5}))
    assert Scores.get_best("iidx", "1001", 2000, 2, "0").miss == 5

    assert {:ok, _} = Scores.record_attempt(iidx_event(%{miss: 3}))
    assert Scores.get_best("iidx", "1001", 2000, 2, "0").miss == 3

    assert {:ok, _} = Scores.record_attempt(iidx_event(%{miss: -1}))
    assert Scores.get_best("iidx", "1001", 2000, 2, "0").miss == 3
  end

  test "failure injection at each stage rolls back the entire transaction" do
    for stage <- [:claim, :attempt, :best, :stats, :outbox, :dual_write, :response] do
      cleanup()

      hook = fn
        ^stage -> raise "injected fault at #{stage}"
        _ -> :ok
      end

      event = iidx_event(%{dual_write: fn _recorded -> :ok end})
      assert {:error, _reason} = Scores.record_attempt(event, stage_hook: hook)

      assert Repo.aggregate(PlayAttempt, :count) == 0, "stage #{stage}"
      assert Repo.aggregate(BestScore, :count) == 0, "stage #{stage}"
      assert Repo.aggregate(ScoreStat, :count) == 0, "stage #{stage}"
      assert Repo.aggregate(IdempotencyKey, :count) == 0, "stage #{stage}"
      assert Repo.aggregate(OutboxEvent, :count) == 0, "stage #{stage}"
    end
  end

  test "a failed submission leaves the idempotency key unclaimed and retryable" do
    event = iidx_event(%{idempotency: %{key: "retry-me", scope: "test", payload_hash: "h"}})

    hook = fn
      :stats -> raise "boom"
      _ -> :ok
    end

    assert {:error, _} = Scores.record_attempt(event, stage_hook: hook)
    assert {:ok, %{status: :recorded}} = Scores.record_attempt(event)
    assert Repo.aggregate(PlayAttempt, :count) == 1
  end

  test "SQL merge and pure merge agree on a sequence of plays" do
    spec = Merge.spec("iidx")

    e1 = iidx_event()
    e2 = iidx_event(%{score: 1200, clear: 7, miss: 1, payload: iidx_payload(%{"ghost" => "zz"})})
    e3 = iidx_event(%{score: 1800, clear: 3, miss: 8, payload: iidx_payload(%{"ghost" => "yy"})})

    for e <- [e1, e2, e3] do
      assert {:ok, %{status: :recorded}} = Scores.record_attempt(e)
    end

    to_row = fn e -> %{score: e.score, clear: e.clear, miss: e.miss, payload: e.payload} end

    expected =
      [e1, e2, e3]
      |> Enum.map(to_row)
      |> Enum.reduce(nil, fn new, acc -> Merge.merge(spec, acc, new) end)

    best = Scores.get_best("iidx", "1001", 2000, 2, "0")
    assert best.score == expected.score
    assert best.clear == expected.clear
    assert best.miss == expected.miss
    assert best.payload == expected.payload
  end

  describe "IIDX33music reg end-to-end" do
    @model "LDJ:J:A:A:2025091700"

    setup do
      DB.drop_table("shop")
      DB.drop_table("iidx_profile")
      {:ok, _} = Shop.permit("IIDXTESTPCBID0001")

      on_exit(fn ->
        DB.drop_table("shop")
        DB.drop_table("iidx_profile")
      end)

      :ok
    end

    defp reg_body(ex_score) do
      Kbinxml.encode(
        E.e(
          "call",
          E.e(
            "IIDX33music",
            [
              E.e(
                "music_play_log",
                [
                  E.e("ghost", "aa00", __type: "bin"),
                  E.e("ghost_gauge", "bb11", __type: "bin")
                ],
                play_style: 0,
                ex_score: ex_score,
                folder_type: 0,
                gauge_type: 0,
                graph_type: 0,
                great_num: 100,
                iidx_id: 1001,
                miss_num: 3,
                mode_type: 0,
                music_id: 2000,
                note_id: 2,
                option1: 0,
                option2: 0,
                pgreat_num: 200
              )
            ],
            method: "reg",
            cflg: 4,
            clid: 2,
            is_death: 0,
            pid: 13
          ),
          model: @model,
          srcid: "IIDXTESTPCBID0001"
        )
      )
    end

    defp reg_post(body) do
      conn(:post, "/local/#{@model}/IIDX33music/reg", body)
      |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
      |> Plug.Conn.put_req_header("content-length", to_string(byte_size(body)))
      |> BaconNet.Router.call(BaconNet.Router.init([]))
    end

    test "a byte-identical retry returns the same response without duplicate effects" do
      body = reg_body(1500)

      conn1 = reg_post(body)
      assert conn1.status == 200

      root1 = Kbinxml.decode(conn1.resp_body).node
      mod1 = XNode.child(root1, "IIDX33music")
      assert XNode.attr(mod1, "crate") == "1000"
      assert XNode.attr(mod1, "frate") == "0"
      assert XNode.attr(mod1, "mid") == "2000"

      assert Repo.aggregate(PlayAttempt, :count) == 1
      assert Scores.get_stats("iidx", 2000, 2, "0").play_count == 1
      assert length(DB.all("iidx_scores")) == 1
      assert length(DB.all("iidx_scores_best")) == 1

      # client retry after a timeout: same body, same response, no duplicates
      conn2 = reg_post(body)
      assert conn2.status == 200
      assert conn2.resp_body == conn1.resp_body

      assert Repo.aggregate(PlayAttempt, :count) == 1
      assert Scores.get_stats("iidx", 2000, 2, "0").play_count == 1
      assert length(DB.all("iidx_scores")) == 1
      assert length(DB.all("iidx_scores_best")) == 1
      assert Repo.aggregate(OutboxEvent, :count) == 1

      # a different play (different score) is a new event and commits
      conn3 = reg_post(reg_body(1600))
      assert conn3.status == 200
      assert Repo.aggregate(PlayAttempt, :count) == 2

      root3 = Kbinxml.decode(conn3.resp_body).node
      assert root3 |> XNode.child("IIDX33music") |> XNode.attr("crate") == "1000"
    end
  end
end

defmodule BaconNet.ScoresMergeTest do
  use ExUnit.Case, async: true

  alias BaconNet.Scores.Merge

  defp row(score, clear, miss, payload) do
    %{score: score, clear: clear, miss: miss, payload: payload}
  end

  defp iidx_row(score, clear, miss, ghost) do
    row(score, clear, miss, %{
      "ghost" => ghost,
      "ghost_gauge" => "g-#{ghost}",
      "gauge_type" => 0,
      "game_version" => 33,
      "pid" => 13
    })
  end

  test "merge with no prior row returns the new row" do
    new = row(100, 4, 3, %{"ghost" => "aa"})
    assert Merge.merge(Merge.spec("iidx"), nil, new) == new
  end

  test "score and clear are monotonic" do
    spec = Merge.spec("iidx")

    merged = Merge.merge(spec, iidx_row(1500, 4, 3, "a"), iidx_row(1200, 7, 1, "b"))

    assert merged.score == 1500
    assert merged.clear == 7

    merged = Merge.merge(spec, iidx_row(1200, 7, 1, "b"), iidx_row(1500, 4, 3, "a"))

    assert merged.score == 1500
    assert merged.clear == 7
  end

  test "iidx miss rule: min, with -1 treated as unknown" do
    spec = Merge.spec("iidx")

    assert Merge.merge(spec, iidx_row(0, 0, 5, "a"), iidx_row(0, 0, 3, "b")).miss == 3
    assert Merge.merge(spec, iidx_row(0, 0, -1, "a"), iidx_row(0, 0, 3, "b")).miss == 3
    assert Merge.merge(spec, iidx_row(0, 0, 3, "a"), iidx_row(0, 0, -1, "b")).miss == 3
    assert Merge.merge(spec, iidx_row(0, 0, -1, "a"), iidx_row(0, 0, -1, "b")).miss == -1
  end

  test "follow_score fields go to the better score, ties to the new play" do
    spec = Merge.spec("iidx")

    merged = Merge.merge(spec, iidx_row(1500, 0, 0, "old"), iidx_row(1200, 0, 0, "new"))
    assert merged.payload["ghost"] == "old"

    merged = Merge.merge(spec, iidx_row(1500, 0, 0, "old"), iidx_row(1500, 0, 0, "new"))
    assert merged.payload["ghost"] == "new"
  end

  test "overwrite fields always take the new value" do
    spec = Merge.spec("iidx")

    old = put_in(iidx_row(1500, 0, 0, "a").payload["pid"], 13)
    new = put_in(iidx_row(1200, 0, 0, "b").payload["pid"], 99)

    assert Merge.merge(spec, old, new).payload["pid"] == 99
  end

  test "ddr rank improves downward while lamp/exscore improve upward" do
    spec = Merge.spec("ddr")

    ddr_row = fn score, lamp, rank, exscore, ghost ->
      row(score, lamp, nil, %{
        "rank" => rank,
        "exscore" => exscore,
        "flare_force" => 2,
        "ghost" => ghost,
        "ghostsize" => 10,
        "game_version" => 20,
        "playstyle" => 0
      })
    end

    new_row = ddr_row.(800_000, 4, 1, 90, "g2")
    new_row = put_in(new_row.payload["flare_force"], 5)

    merged = Merge.merge(spec, ddr_row.(900_000, 2, 3, 100, "g1"), new_row)

    assert merged.score == 900_000
    assert merged.clear == 4
    assert merged.payload["rank"] == 1
    assert merged.payload["exscore"] == 100
    assert merged.payload["flare_force"] == 5
    assert merged.payload["ghost"] == "g1"
  end

  test "gitadora meter follows perc; skill/fullcombo/excellent are monotonic" do
    spec = Merge.spec("drummania")

    merged =
      Merge.merge(
        spec,
        row(9000, 1, nil, %{
          "skill" => 500,
          "fullcombo" => 1,
          "excellent" => 0,
          "rank" => 3,
          "meter" => 7,
          "meter_prog" => 1
        }),
        row(8500, 1, nil, %{
          "skill" => 600,
          "fullcombo" => 0,
          "excellent" => 1,
          "rank" => 5,
          "meter" => 9,
          "meter_prog" => 9
        })
      )

    assert merged.score == 9000
    assert merged.payload["skill"] == 600
    assert merged.payload["fullcombo"] == 1
    assert merged.payload["excellent"] == 1
    assert merged.payload["rank"] == 5
    assert merged.payload["meter"] == 7
  end

  test "specs only contain SQL-safe payload field names" do
    for {game, spec} <- Merge.specs() do
      fields =
        spec.payload_max ++
          spec.payload_min ++
          spec.payload_follow_score ++
          spec.payload_overwrite

      assert fields == Enum.uniq(fields), "duplicate payload fields in #{game} spec"

      for f <- fields do
        assert f =~ ~r/^[a-z0-9_]+$/, "unsafe field #{f} in #{game} spec"
      end
    end
  end
end
