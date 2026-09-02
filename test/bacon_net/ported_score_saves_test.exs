defmodule BaconNet.PortedScoreSavesTest do
  @moduledoc """
  End-to-end coverage for the score-save handlers ported from the legacy
  insert/read/upsert path to the transactional `BaconNet.Scores` command:
  iidx29music/music reg, ddr playerdata/playerdata_2 usersave, sdvx
  save_m, drs save_musicscore, nostalgia set_stage_result. Each test posts
  a real kbin request through the router, checks the protocol response,
  then replays the byte-identical body and asserts no duplicate effects.
  """

  use ExUnit.Case, async: false

  import Ecto.Query
  import Plug.Test

  alias BaconNet.{DB, E, Kbinxml, Repo, Shop, XNode}
  alias BaconNet.Scores.{IdempotencyKey, OutboxEvent, PlayAttempt}

  @pcbid "PORTEDTESTPCBID001"

  @doc_tables [
    "iidx_scores",
    "iidx_scores_best",
    "iidx_score_stats",
    "iidx_profile",
    "ddr_scores",
    "ddr_scores_best",
    "ddr_profile",
    "sdvx_scores",
    "sdvx_scores_best",
    "sdvx_profile",
    "drs_scores",
    "drs_scores_best",
    "dancerush_profile",
    "nostalgia_scores",
    "nostalgia_scores_best",
    "nostalgia_profile"
  ]

  setup do
    cleanup()
    DB.drop_table("shop")
    {:ok, _} = Shop.permit(@pcbid)

    on_exit(fn ->
      cleanup()
      DB.drop_table("shop")
    end)

    :ok
  end

  defp cleanup do
    Repo.delete_all(PlayAttempt)
    Repo.delete_all(BaconNet.Scores.BestScore)
    Repo.delete_all(BaconNet.Scores.ScoreStat)
    Repo.delete_all(IdempotencyKey)
    Repo.delete_all(OutboxEvent)
    Enum.each(@doc_tables, &DB.drop_table/1)
    :ok
  end

  defp kbin_post(path, model, module_node) do
    body = Kbinxml.encode(E.e("call", module_node, model: model, srcid: @pcbid))

    conn(:post, path, body)
    |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
    |> Plug.Conn.put_req_header("content-length", to_string(byte_size(body)))
    |> BaconNet.Router.call(BaconNet.Router.init([]))
  end

  defp decode(conn), do: Kbinxml.decode(conn.resp_body).node

  defp attempts(game) do
    Repo.all(from(a in PlayAttempt, where: a.game == ^game))
  end

  ## IIDX v29 reg

  @iidx29_model "LDJ:J:A:A:2021101300"

  defp iidx29_body(ex_score) do
    E.e(
      "IIDX29music",
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
    )
  end

  test "iidx29music reg records atomically and replays byte-identically" do
    path = "/local2/#{@iidx29_model}/IIDX29music/reg"

    conn1 = kbin_post(path, @iidx29_model, iidx29_body(1500))
    assert conn1.status == 200

    mod = XNode.child(decode(conn1), "IIDX29music")
    assert XNode.attr(mod, "crate") == "1000"
    assert XNode.attr(mod, "mid") == "2000"

    assert [attempt] = attempts("iidx")
    assert attempt.version == 29
    assert attempt.player == "1001"
    assert attempt.song == 2000
    assert attempt.score == 1500

    assert length(DB.all("iidx_scores")) == 1
    assert length(DB.all("iidx_scores_best")) == 1
    assert Repo.aggregate(OutboxEvent, :count) == 1

    conn2 = kbin_post(path, @iidx29_model, iidx29_body(1500))
    assert conn2.status == 200
    assert conn2.resp_body == conn1.resp_body

    assert length(attempts("iidx")) == 1
    assert length(DB.all("iidx_scores")) == 1
    assert Repo.aggregate(OutboxEvent, :count) == 1
  end

  ## Legacy IIDX (shared `music` module), game version 20

  @legacy_model "LDJ:J:A:A:2012010100"

  defp legacy_body(cflg) do
    E.e(
      "music",
      [E.e("ghost", "aa00", __type: "bin")],
      method: "reg",
      cflg: cflg,
      clid: 1,
      gnum: 100,
      iidxid: 1001,
      mnum: 3,
      pgnum: 200,
      pid: 13,
      is_death: 0,
      mid: 2000
    )
  end

  test "legacy music reg (v20) records atomically and replays" do
    path = "/local/#{@legacy_model}/music/reg"

    conn1 = kbin_post(path, @legacy_model, legacy_body(4))
    assert conn1.status == 200

    mod = XNode.child(decode(conn1), "music")
    # legacy divides the per-mille rates by 10
    assert XNode.attr(mod, "crate") == "100"
    assert XNode.attr(mod, "mid") == "2000"

    # ex_score = pgreat*2 + great = 500; clid 1 -> note_id 2, play_style 0
    assert [attempt] = attempts("iidx")
    assert attempt.version == 20
    assert attempt.chart == 2
    assert attempt.score == 500

    conn2 = kbin_post(path, @legacy_model, legacy_body(4))
    assert conn2.status == 200
    assert conn2.resp_body == conn1.resp_body

    assert length(attempts("iidx")) == 1
    assert length(DB.all("iidx_scores")) == 1
    assert Repo.aggregate(IdempotencyKey, :count) == 1
  end

  ## DDR A20 (playerdata) / A3 (playerdata_2) usersave

  defp ddr_note(score) do
    E.e("note", [
      E.e("stagenum", 1, __type: "s32"),
      E.e("mcode", 555, __type: "s32"),
      E.e("notetype", 1, __type: "s32"),
      E.e("rank", 3, __type: "s32"),
      E.e("clearkind", 2, __type: "s32"),
      E.e("score", score, __type: "s32"),
      E.e("exscore", 10, __type: "s32"),
      E.e("maxcombo", 100, __type: "s32"),
      E.e("life", 50, __type: "s32"),
      E.e("fastcount", 1, __type: "s32"),
      E.e("slowcount", 2, __type: "s32"),
      E.e("judge_marvelous", 10, __type: "s32"),
      E.e("judge_perfect", 20, __type: "s32"),
      E.e("judge_great", 30, __type: "s32"),
      E.e("judge_good", 5, __type: "s32"),
      E.e("judge_boo", 0, __type: "s32"),
      E.e("judge_miss", 1, __type: "s32"),
      E.e("judge_ok", 40, __type: "s32"),
      E.e("judge_ng", 0, __type: "s32"),
      E.e("calorie", 12, __type: "s32"),
      E.e("ghostsize", 4, __type: "s32"),
      E.e("ghost", "aabb", __type: "str"),
      E.e("opt_speed", 2, __type: "s32"),
      E.e("opt_boost", 0, __type: "s32"),
      E.e("opt_appearance", 0, __type: "s32"),
      E.e("opt_turn", 0, __type: "s32"),
      E.e("opt_dark", 0, __type: "s32"),
      E.e("opt_scroll", 0, __type: "s32"),
      E.e("opt_arrowcolor", 0, __type: "s32"),
      E.e("opt_cut", 0, __type: "s32"),
      E.e("opt_freeze", 0, __type: "s32"),
      E.e("opt_jump", 0, __type: "s32"),
      E.e("opt_arrowshape", 0, __type: "s32"),
      E.e("opt_filter", 0, __type: "s32"),
      E.e("opt_guideline", 0, __type: "s32"),
      E.e("opt_gauge", 0, __type: "s32"),
      E.e("opt_judgepriority", 0, __type: "s32"),
      E.e("opt_timing", 0, __type: "s32")
    ])
  end

  defp ddr_usersave_node(module, score) do
    E.e(
      module,
      [
        E.e("data", [
          E.e("mode", "usersave", __type: "str"),
          E.e("gamesession", "1", __type: "str"),
          E.e("refid", "E0040011223344", __type: "str"),
          E.e("ddrcode", 555, __type: "s32"),
          E.e("playstyle", 0, __type: "s32"),
          E.e("pcbid", @pcbid, __type: "str"),
          E.e("shoparea", "1", __type: "str"),
          E.e("isgameover", 0, __type: "s32"),
          ddr_note(score)
        ])
      ],
      method: "usergamedata_advanced"
    )
  end

  test "ddr playerdata usersave (A20/v19) records atomically and replays" do
    model = "MDX:J:A:A:2019022600"
    path = "/local2/#{model}/playerdata/usergamedata_advanced"

    conn1 = kbin_post(path, model, ddr_usersave_node("playerdata", 900_000))
    assert conn1.status == 200

    mod = XNode.child(decode(conn1), "playerdata")
    assert mod |> XNode.child("result") |> Map.get(:text) == "0"

    assert [attempt] = attempts("ddr")
    assert attempt.player == "555"
    assert attempt.song == 555
    assert attempt.score == 900_000

    assert length(DB.all("ddr_scores")) == 1

    [best_doc] = DB.all("ddr_scores_best")
    assert best_doc["score"] == 900_000
    assert best_doc["ghostid"] != nil

    conn2 = kbin_post(path, model, ddr_usersave_node("playerdata", 900_000))
    assert conn2.status == 200
    assert conn2.resp_body == conn1.resp_body

    assert length(attempts("ddr")) == 1
    assert length(DB.all("ddr_scores")) == 1
    assert Repo.aggregate(OutboxEvent, :count) == 1
  end

  test "ddr playerdata_2 usersave (A3/v20) records atomically and replays" do
    model = "MDX:J:A:A:2024061200"
    path = "/local2/#{model}/playerdata_2/usergamedata_advanced"

    conn1 = kbin_post(path, model, ddr_usersave_node("playerdata_2", 800_000))
    assert conn1.status == 200

    mod = XNode.child(decode(conn1), "playerdata_2")
    assert mod |> XNode.child("result") |> Map.get(:text) == "0"

    assert [attempt] = attempts("ddr")
    assert attempt.score == 800_000

    conn2 = kbin_post(path, model, ddr_usersave_node("playerdata_2", 800_000))
    assert conn2.status == 200
    assert conn2.resp_body == conn1.resp_body
    assert length(attempts("ddr")) == 1
  end

  ## SDVX save_m

  test "sdvx save_m records atomically and replays" do
    model = "KFC:J:A:A:2020090402"
    refid = "SDVXTESTREFID0001"

    DB.insert("sdvx_profile", %{
      "card" => refid,
      "sdvx_id" => 1234,
      "version" => %{"6" => %{"name" => "TESTUSER"}}
    })

    node =
      E.e(
        "game",
        [
          E.e("dataid", refid, __type: "str"),
          E.e("track", [
            E.e("play_id", 1, __type: "s32"),
            E.e("music_id", 100, __type: "s32"),
            E.e("music_type", 2, __type: "s32"),
            E.e("score", 9_000_000, __type: "s32"),
            E.e("exscore", 500, __type: "s32"),
            E.e("clear_type", 2, __type: "s32"),
            E.e("score_grade", 4, __type: "s32"),
            E.e("max_chain", 800, __type: "s32"),
            E.e("just", 100, __type: "s32"),
            E.e("critical", 200, __type: "s32"),
            E.e("near", 50, __type: "s32"),
            E.e("error", 3, __type: "s32"),
            E.e("effective_rate", 1, __type: "s32"),
            E.e("btn_rate", 80, __type: "s32"),
            E.e("long_rate", 90, __type: "s32"),
            E.e("vol_rate", 95, __type: "s32"),
            E.e("mode", 0, __type: "s32"),
            E.e("gauge_type", 0, __type: "s32"),
            E.e("notes_option", 0, __type: "s32"),
            E.e("online_num", 0, __type: "s32"),
            E.e("local_num", 0, __type: "s32"),
            E.e("challenge_type", 0, __type: "s32"),
            E.e("retry_cnt", 0, __type: "s32"),
            E.e("judge", [1, 2, 3], __type: "s32")
          ])
        ],
        method: "sv6_save_m"
      )

    path = "/local2/#{model}/game/sv6_save_m"

    conn1 = kbin_post(path, model, node)
    assert conn1.status == 200
    assert XNode.child(decode(conn1), "game") != nil

    assert [attempt] = attempts("sdvx")
    assert attempt.player == "1234"
    assert attempt.song == 100
    assert attempt.chart == 2
    assert attempt.play_style == "6"
    assert attempt.score == 9_000_000

    [best_doc] = DB.all("sdvx_scores_best")
    assert best_doc["score"] == 9_000_000
    assert best_doc["name"] == "TESTUSER"

    conn2 = kbin_post(path, model, node)
    assert conn2.status == 200
    assert conn2.resp_body == conn1.resp_body

    assert length(attempts("sdvx")) == 1
    assert length(DB.all("sdvx_scores")) == 1
  end

  ## DANCERUSH save_musicscore

  test "drs save_musicscore records atomically and replays" do
    model = "QCV:J:A:A:2018080100"
    refid = "DRSTESTREFID00001"

    DB.insert("dancerush_profile", %{
      "card" => refid,
      "drs_id" => 777,
      "version" => %{"0" => %{"name" => "DRSUSER"}}
    })

    node =
      E.e(
        "game",
        [
          E.e("data", [
            E.e("userid", E.e("refid", refid, __type: "str")),
            E.e("music_id", 10, __type: "s32"),
            E.e("music_type", "1", __type: "str"),
            E.e("mode", 0, __type: "s32"),
            E.e("score", 900, __type: "s32"),
            E.e("rank", 3, __type: "s32"),
            E.e("combo", 100, __type: "s32"),
            E.e("param", 5, __type: "s32"),
            E.e("member", [
              E.e("perfect", 50, __type: "s32"),
              E.e("great", 40, __type: "s32"),
              E.e("good", 10, __type: "s32"),
              E.e("bad", 0, __type: "s32")
            ])
          ])
        ],
        method: "save_musicscore"
      )

    path = "/local/#{model}/game/save_musicscore"

    conn1 = kbin_post(path, model, node)
    assert conn1.status == 200
    assert XNode.child(decode(conn1), "game") != nil

    assert [attempt] = attempts("drs")
    assert attempt.player == "777"
    assert attempt.song == 10
    assert attempt.play_style == "0:1"
    assert attempt.score == 900

    [best_doc] = DB.all("drs_scores_best")
    assert best_doc["score"] == 900
    assert best_doc["name"] == "DRSUSER"

    conn2 = kbin_post(path, model, node)
    assert conn2.status == 200
    assert conn2.resp_body == conn1.resp_body

    assert length(attempts("drs")) == 1
    assert length(DB.all("drs_scores")) == 1
  end

  ## NOSTALGIA set_stage_result

  test "nostalgia set_stage_result records atomically and replays" do
    model = "N01:J:A:A:2019010100"
    refid = "NOSTESTREFID00001"

    DB.insert("nostalgia_profile", %{"card" => refid, "nostalgia_id" => 555})

    counts = fn prefix ->
      E.e(prefix, [
        E.e("miss", 1, __type: "s32"),
        E.e("good", 2, __type: "s32"),
        E.e("just", 3, __type: "s32"),
        E.e("super_just", 4, __type: "s32"),
        E.e("near", 5, __type: "s32")
      ])
    end

    common =
      E.e("common", [
        E.e("play_time", 1_700_000_000, __type: "s32"),
        E.e("score", 950_000, __type: "s32"),
        E.e("combo", 300, __type: "s32"),
        E.e("grade", 5, __type: "s32"),
        E.e("hands_mode", 0, __type: "s32"),
        E.e("play_count", 1, __type: "s32"),
        E.e("clear_count", 1, __type: "s32"),
        E.e("multi_count", 0, __type: "s32"),
        E.e("clear_flag", 1, __type: "s32"),
        E.e("slow_count", 2, __type: "s32"),
        E.e("fast_count", 3, __type: "s32"),
        counts.("judge_count"),
        counts.("judge_percent_max_count_long"),
        counts.("judge_percent_max_count_trill"),
        E.e("note_num", [
          E.e("normal", 100, __type: "s32"),
          E.e("long", 10, __type: "s32"),
          E.e("glissando", 5, __type: "s32"),
          E.e("trill", 2, __type: "s32")
        ]),
        E.e("note_success_rate", [
          E.e("normal", 90, __type: "s32"),
          E.e("long", 95, __type: "s32"),
          E.e("glissando", 80, __type: "s32"),
          E.e("trill", 70, __type: "s32")
        ]),
        E.e("best_score", 900_000, __type: "s32")
      ])

    node =
      E.e(
        "op3_player",
        [
          E.e("refid", refid, __type: "str"),
          E.e("stageinfo", [E.e("stage", [common], music_index: 42, sheet_type: 1)])
        ],
        method: "set_stage_result"
      )

    path = "/local/#{model}/op3_player/set_stage_result"

    conn1 = kbin_post(path, model, node)
    assert conn1.status == 200
    assert XNode.child(decode(conn1), "set_stage_result") != nil

    assert [attempt] = attempts("nostalgia")
    assert attempt.player == "555"
    assert attempt.song == 42
    assert attempt.chart == 1
    assert attempt.score == 950_000

    [best_doc] = DB.all("nostalgia_scores_best")
    assert best_doc["score"] == 950_000
    assert best_doc["grade"] == 5

    conn2 = kbin_post(path, model, node)
    assert conn2.status == 200
    assert conn2.resp_body == conn1.resp_body

    assert length(attempts("nostalgia")) == 1
    assert length(DB.all("nostalgia_scores")) == 1
  end
end
