defmodule BaconNet.Modules.Nostalgia.Op3Player do
  @moduledoc "Port of modules/nostalgia/op3_player.py."

  alias BaconNet.{Core, DB, E, XNode}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"op3_player", "regist_playdata", :op3_player_regist_playdata},
        {"op3_player", "get_musicdata", :op3_player_get_musicdata},
        {"op3_player", "get_playdata", :op3_player_get_playdata},
        {"op3_player", "set_stage_result", :op3_player_set_stage_result},
        {"op3_player", "set_total_result", :op3_player_set_total_result}
      ]
    }
  end

  @last_keys [
    "music_group",
    "music_index",
    "sheet_type",
    "perform_type",
    "filter_flag",
    "brooch_index",
    "hi_speed_level",
    "beat_guide",
    "headphone_volume",
    "judge_bar_pos",
    "hands_mode",
    "near_setting",
    "judge_delay_offset",
    "key_beam_level",
    "orbit_type",
    "note_height",
    "note_width",
    "judge_width_type",
    "beat_guide_volume",
    "beat_guide_type",
    "key_volume_offset",
    "bgm_volume_offset",
    "note_disp_type",
    "slow_fast",
    "option_setting",
    "judge_effect_adjust",
    "simple_bg",
    "bingo_index",
    "class_basic",
    "class_recital",
    "grade_basic",
    "grade_recital"
  ]

  @travel_keys [
    "money",
    "pianist_power",
    "fame_index",
    "kingdom_id",
    "quest_index"
  ]

  defp get_profile(cid) do
    DB.get("nostalgia_profile", %{"card" => cid})
  end

  defp get_game_profile(cid, game_version) do
    profile = get_profile(cid)
    get_in(profile || %{}, ["version", to_string(game_version)])
  end

  def op3_player_regist_playdata(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    root = Core.module_node(info)

    dataid = root |> XNode.child("dataid") |> text()
    _refid = root |> XNode.child("refid") |> text()
    name = root |> XNode.child("name") |> text()

    all_profiles_for_card =
      DB.get("nostalgia_profile", %{"card" => dataid}) || %{"card" => dataid, "version" => %{}}

    all_profiles_for_card =
      if Map.has_key?(all_profiles_for_card, "nostalgia_id") do
        all_profiles_for_card
      else
        Map.put(all_profiles_for_card, "nostalgia_id", :rand.uniform(90_000_000) + 9_999_999)
      end

    version = %{
      "game_version" => game_version,
      "name" => name,
      "music_group" => 0,
      "music_index" => 0,
      "sheet_type" => 0,
      "perform_type" => 0,
      "filter_flag" => 0,
      "brooch_index" => 0,
      "hi_speed_level" => 0,
      "beat_guide" => 0,
      "headphone_volume" => 0,
      "judge_bar_pos" => 250,
      "hands_mode" => 0,
      "near_setting" => 0,
      "judge_delay_offset" => 0,
      "key_beam_level" => 0,
      "orbit_type" => 0,
      "note_height" => 10,
      "note_width" => 10,
      "judge_width_type" => 10,
      "beat_guide_volume" => 0,
      "beat_guide_type" => 0,
      "key_volume_offset" => 0,
      "bgm_volume_offset" => 0,
      "note_disp_type" => 0,
      "slow_fast" => 0,
      "option_setting" => 0,
      "judge_effect_adjust" => 0,
      "simple_bg" => 0,
      "bingo_index" => 0,
      "class_basic" => 0,
      "class_recital" => 0,
      "grade_basic" => 0,
      "grade_recital" => 0,
      "money" => 0,
      "pianist_power" => 0,
      "fame_index" => 0,
      "kingdom_id" => 0,
      "quest_index" => 0,
      "param1" => [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      "param2" => [0, 0, 0, 0, 0, 0, 0, 0]
    }

    all_profiles_for_card =
      put_in(all_profiles_for_card, ["version", to_string(game_version)], version)

    DB.upsert("nostalgia_profile", all_profiles_for_card, %{"card" => dataid})

    flags = List.duplicate(-1, 32)

    response =
      E.e(
        "response",
        E.e("regist_playdata", [
          E.e("permitted_list", [
            E.e("flag", flags, __type: "s32", sheet_type: "0"),
            E.e("flag", flags, __type: "s32", sheet_type: "1"),
            E.e("flag", flags, __type: "s32", sheet_type: "2"),
            E.e("flag", flags, __type: "s32", sheet_type: "3")
          ]),
          E.e("valid_quest_list", E.e("quest", index: "1")),
          E.e("valid_course_list", E.e("course", index: "1")),
          E.e("name", name, __type: "str"),
          E.e("play_count", 0, __type: "s32"),
          E.e("today_play_count", 0, __type: "s32"),
          E.e("old_play_count", 0, __type: "s32"),
          E.e("old_recital_count", 0, __type: "s32"),
          E.e("music_list", [
            E.e("flag", flags, __type: "s32", sheet_type: "0"),
            E.e("flag", flags, __type: "s32", sheet_type: "1"),
            E.e("flag", flags, __type: "s32", sheet_type: "2"),
            E.e("flag", flags, __type: "s32", sheet_type: "3")
          ]),
          E.e("free_for_play_music_list", [
            E.e("flag", flags, __type: "s32", sheet_type: "0"),
            E.e("flag", flags, __type: "s32", sheet_type: "1"),
            E.e("flag", flags, __type: "s32", sheet_type: "2"),
            E.e("flag", flags, __type: "s32", sheet_type: "3")
          ]),
          E.e("last", [
            E.e("music_group", 0, __type: "s32"),
            E.e("music_index", 0, __type: "s32"),
            E.e("sheet_type", 0, __type: "s8"),
            E.e("perform_type", 0, __type: "s32"),
            E.e("filter_flag", 0, __type: "u64"),
            E.e("brooch_index", 0, __type: "s32"),
            E.e("hi_speed_level", 0, __type: "s32"),
            E.e("beat_guide", 0, __type: "s8"),
            E.e("headphone_volume", 0, __type: "s8"),
            E.e("judge_bar_pos", 0, __type: "s32"),
            E.e("hands_mode", 0, __type: "s8"),
            E.e("near_setting", 0, __type: "s8"),
            E.e("judge_delay_offset", 0, __type: "s8"),
            E.e("key_beam_level", 0, __type: "s8"),
            E.e("orbit_type", 0, __type: "s8"),
            E.e("note_height", 0, __type: "s8"),
            E.e("note_width", 0, __type: "s8"),
            E.e("judge_width_type", 0, __type: "s8"),
            E.e("beat_guide_volume", 0, __type: "s8"),
            E.e("beat_guide_type", 0, __type: "s8"),
            E.e("key_volume_offset", 0, __type: "s8"),
            E.e("bgm_volume_offset", 0, __type: "s8"),
            E.e("note_disp_type", 0, __type: "s8"),
            E.e("slow_fast", 0, __type: "s8"),
            E.e("option_setting", 0, __type: "s32"),
            E.e("judge_effect_adjust", 0, __type: "s8"),
            E.e("simple_bg", 0, __type: "s8"),
            E.e("bingo_index", 0, __type: "s32")
          ]),
          E.e("travel", [
            E.e("money", 0, __type: "s32"),
            E.e("pianist_power", 0, __type: "s32"),
            E.e("fame_index", 0, __type: "s32"),
            E.e("kingdom_id", 0, __type: "s32"),
            E.e("quest_index", 0, __type: "s32")
          ])
          # E.brooch_list(),
          # E.enquete_list(),
          # E.event_list(),
        ])
      )

    Core.send_response(conn, info, response)
  end

  def op3_player_get_musicdata(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    refid = Core.module_node(info) |> XNode.child("refid") |> text()
    _profile = get_game_profile(refid, game_version)
    nostalgia_id = get_profile(refid)["nostalgia_id"]

    records = DB.search("nostalgia_scores_best", %{"nostalgia_id" => nostalgia_id})

    music_nodes =
      for r <- records do
        E.e(
          "music",
          [
            E.e("recital", [
              E.e("score", r["score"], __type: "s32"),
              E.e("play_count", r["play_count"], __type: "s32"),
              E.e("clear_count", r["clear_count"], __type: "s32"),
              E.e("multi_count", r["multi_count"], __type: "s32"),
              E.e("clear_flag", r["clear_flag"], __type: "s32"),
              E.e("hands_mode", r["hands_mode"], __type: "s8"),
              E.e("evaluation", 5, __type: "u32"),
              E.e("grade", r["grade"], __type: "u32")
            ]),
            E.e("score", r["score"], __type: "s32"),
            E.e("play_count", r["play_count"], __type: "s32"),
            E.e("clear_count", r["clear_count"], __type: "s32"),
            E.e("multi_count", r["multi_count"], __type: "s32"),
            E.e("clear_flag", r["clear_flag"], __type: "s32"),
            E.e("hands_mode", r["hands_mode"], __type: "s8"),
            E.e("evaluation", 5, __type: "u32"),
            E.e("grade", r["grade"], __type: "u32")
          ],
          sheet_type: r["sheet_type"],
          music_index: r["music_index"]
        )
      end

    response =
      E.e(
        "response",
        E.e("get_musicdata", non_empty(music_nodes))
        # E.new_music_list(
        #    *[E.music(
        #        E.unlock_time(0, __type="u64"),
        #        sheet_type="2",
        #        music_index=x
        #    )for x in range(1,300)],
        # ),
      )

    Core.send_response(conn, info, response)
  end

  def op3_player_get_playdata(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    refid = Core.module_node(info) |> XNode.child("refid") |> text()
    profile = get_game_profile(refid, game_version)

    flags = List.duplicate(-1, 32)

    response =
      E.e(
        "response",
        E.e("get_playdata", [
          E.e("permitted_list", [
            E.e("flag", flags, __type: "s32", sheet_type: "0"),
            E.e("flag", flags, __type: "s32", sheet_type: "1"),
            E.e("flag", flags, __type: "s32", sheet_type: "2"),
            E.e("flag", flags, __type: "s32", sheet_type: "3")
          ]),
          # E.valid_quest_list(
          #    E.quest(index="1")
          # ),
          # E.valid_course_list(
          #    E.course(index="1")
          # ),
          E.e("name", profile["name"], __type: "str"),
          E.e("play_count", 0, __type: "s32"),
          E.e("today_play_count", 0, __type: "s32"),
          E.e("old_play_count", 0, __type: "s32"),
          E.e("old_recital_count", 0, __type: "s32"),
          E.e("music_list", [
            E.e("flag", flags, __type: "s32", sheet_type: "0"),
            E.e("flag", flags, __type: "s32", sheet_type: "1"),
            E.e("flag", flags, __type: "s32", sheet_type: "2"),
            E.e("flag", flags, __type: "s32", sheet_type: "3")
          ]),
          E.e("free_for_play_music_list", [
            E.e("flag", flags, __type: "s32", sheet_type: "0"),
            E.e("flag", flags, __type: "s32", sheet_type: "1"),
            E.e("flag", flags, __type: "s32", sheet_type: "2"),
            E.e("flag", flags, __type: "s32", sheet_type: "3")
          ]),
          E.e("last", [
            E.e("music_group", profile["music_group"], __type: "s32"),
            E.e("music_index", profile["music_index"], __type: "s32"),
            E.e("sheet_type", profile["sheet_type"], __type: "s8"),
            E.e("perform_type", profile["perform_type"], __type: "s32"),
            E.e("filter_flag", profile["filter_flag"], __type: "u64"),
            E.e("brooch_index", profile["brooch_index"], __type: "s32"),
            E.e("hi_speed_level", profile["hi_speed_level"], __type: "s32"),
            E.e("beat_guide", profile["beat_guide"], __type: "s8"),
            E.e("headphone_volume", profile["headphone_volume"], __type: "s8"),
            E.e("judge_bar_pos", profile["judge_bar_pos"], __type: "s32"),
            E.e("hands_mode", profile["hands_mode"], __type: "s8"),
            E.e("near_setting", profile["near_setting"], __type: "s8"),
            E.e("judge_delay_offset", profile["judge_delay_offset"], __type: "s8"),
            E.e("key_beam_level", profile["key_beam_level"], __type: "s8"),
            E.e("orbit_type", profile["orbit_type"], __type: "s8"),
            E.e("note_height", profile["note_height"], __type: "s8"),
            E.e("note_width", profile["note_width"], __type: "s8"),
            E.e("judge_width_type", profile["judge_width_type"], __type: "s8"),
            E.e("beat_guide_volume", profile["beat_guide_volume"], __type: "s8"),
            E.e("beat_guide_type", profile["beat_guide_type"], __type: "s8"),
            E.e("key_volume_offset", profile["key_volume_offset"], __type: "s8"),
            E.e("bgm_volume_offset", profile["bgm_volume_offset"], __type: "s8"),
            E.e("note_disp_type", profile["note_disp_type"], __type: "s8"),
            E.e("slow_fast", profile["slow_fast"], __type: "s8"),
            E.e("option_setting", profile["option_setting"], __type: "s32"),
            E.e("judge_effect_adjust", profile["judge_effect_adjust"], __type: "s8"),
            E.e("simple_bg", profile["simple_bg"], __type: "s8"),
            E.e("bingo_index", profile["bingo_index"], __type: "s32"),
            E.e("class_basic", profile["class_basic"], __type: "s32"),
            E.e("class_recital", profile["class_recital"], __type: "s32"),
            E.e("grade_basic", profile["grade_basic"], __type: "s32"),
            E.e("grade_recital", profile["grade_recital"], __type: "s32")
          ]),
          E.e("travel", [
            E.e("money", profile["money"], __type: "s32"),
            E.e("pianist_power", profile["pianist_power"], __type: "s32"),
            E.e("fame_index", profile["fame_index"], __type: "s32"),
            E.e("kingdom_id", profile["kingdom_id"], __type: "s32"),
            E.e("quest_index", profile["quest_index"], __type: "s32")
          ]),
          E.e("extra_param", [
            E.e(
              "param",
              [
                E.e("count", length(profile["param1"]), __type: "s32"),
                E.e("params_array", profile["param1"], __type: "s32")
              ],
              type: "1"
            ),
            E.e(
              "param",
              [
                E.e("count", length(profile["param2"]), __type: "s32"),
                E.e("params_array", profile["param2"], __type: "s32")
              ],
              type: "2"
            )
            # E.param(
            #    E.count(11, __type="s32"),
            #    E.params_array([0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0], __type="s32"),
            #    type="1"
            # ),
            # E.param(
            #    E.count(8, __type="s32"),
            #    E.params_array([64, 0, 0, 0, 0, 0, 0, 0], __type="s32"),
            #    type="2"
            # ),
          ])
          # E.brooch_list(),
          # E.enquete_list(),
          # E.event_list(),
        ])
      )

    Core.send_response(conn, info, response)
  end

  def op3_player_set_stage_result(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    root = Core.module_node(info)

    refid = root |> XNode.child("refid") |> text()
    profile = get_profile(refid)
    nostalgia_id = profile["nostalgia_id"]
    _game_profile = get_in(profile || %{}, ["version", to_string(game_version)]) || %{}

    stageinfo = XNode.child(root, "stageinfo")

    stage = stageinfo |> XNode.children("stage") |> List.last()
    common = XNode.child(stage, "common")

    music_index = stage |> XNode.attr("music_index") |> int()
    sheet_type = stage |> XNode.attr("sheet_type") |> int()
    play_time = common |> XNode.child("play_time") |> text() |> int()
    score = common |> XNode.child("score") |> text() |> int()
    combo = common |> XNode.child("combo") |> text() |> int()
    grade = common |> XNode.child("grade") |> text() |> int()
    hands_mode = common |> XNode.child("hands_mode") |> text() |> int()
    play_count = common |> XNode.child("play_count") |> text() |> int()
    clear_count = common |> XNode.child("clear_count") |> text() |> int()
    multi_count = common |> XNode.child("multi_count") |> text() |> int()
    clear_flag = common |> XNode.child("clear_flag") |> text() |> int()
    slow_count = common |> XNode.child("slow_count") |> text() |> int()
    fast_count = common |> XNode.child("fast_count") |> text() |> int()

    judge_count_miss =
      common |> XNode.child("judge_count") |> XNode.child("miss") |> text() |> int()

    judge_count_good =
      common |> XNode.child("judge_count") |> XNode.child("good") |> text() |> int()

    judge_count_just =
      common |> XNode.child("judge_count") |> XNode.child("just") |> text() |> int()

    judge_count_super_just =
      common |> XNode.child("judge_count") |> XNode.child("super_just") |> text() |> int()

    judge_count_near =
      common |> XNode.child("judge_count") |> XNode.child("near") |> text() |> int()

    judge_percent_max_count_long_miss =
      common
      |> XNode.child("judge_percent_max_count_long")
      |> XNode.child("miss")
      |> text()
      |> int()

    judge_percent_max_count_long_good =
      common
      |> XNode.child("judge_percent_max_count_long")
      |> XNode.child("good")
      |> text()
      |> int()

    judge_percent_max_count_long_just =
      common
      |> XNode.child("judge_percent_max_count_long")
      |> XNode.child("just")
      |> text()
      |> int()

    judge_percent_max_count_long_super_just =
      common
      |> XNode.child("judge_percent_max_count_long")
      |> XNode.child("super_just")
      |> text()
      |> int()

    judge_percent_max_count_long_near =
      common
      |> XNode.child("judge_percent_max_count_long")
      |> XNode.child("near")
      |> text()
      |> int()

    judge_percent_max_count_trill_miss =
      common
      |> XNode.child("judge_percent_max_count_trill")
      |> XNode.child("miss")
      |> text()
      |> int()

    judge_percent_max_count_trill_good =
      common
      |> XNode.child("judge_percent_max_count_trill")
      |> XNode.child("good")
      |> text()
      |> int()

    judge_percent_max_count_trill_just =
      common
      |> XNode.child("judge_percent_max_count_trill")
      |> XNode.child("just")
      |> text()
      |> int()

    judge_percent_max_count_trill_super_just =
      common
      |> XNode.child("judge_percent_max_count_trill")
      |> XNode.child("super_just")
      |> text()
      |> int()

    judge_percent_max_count_trill_near =
      common
      |> XNode.child("judge_percent_max_count_trill")
      |> XNode.child("near")
      |> text()
      |> int()

    note_num_normal =
      common |> XNode.child("note_num") |> XNode.child("normal") |> text() |> int()

    note_num_long = common |> XNode.child("note_num") |> XNode.child("long") |> text() |> int()

    note_num_glissando =
      common |> XNode.child("note_num") |> XNode.child("glissando") |> text() |> int()

    note_num_trill = common |> XNode.child("note_num") |> XNode.child("trill") |> text() |> int()

    note_success_rate_normal =
      common |> XNode.child("note_success_rate") |> XNode.child("normal") |> text() |> int()

    note_success_rate_long =
      common |> XNode.child("note_success_rate") |> XNode.child("long") |> text() |> int()

    note_success_rate_glissando =
      common |> XNode.child("note_success_rate") |> XNode.child("glissando") |> text() |> int()

    note_success_rate_trill =
      common |> XNode.child("note_success_rate") |> XNode.child("trill") |> text() |> int()

    best_score = common |> XNode.child("best_score") |> text() |> int()

    DB.insert("nostalgia_scores", %{
      "timestamp" => play_time,
      "game_version" => game_version,
      "nostalgia_id" => nostalgia_id,
      "music_index" => music_index,
      "sheet_type" => sheet_type,
      "score" => score,
      "combo" => combo,
      "grade" => grade,
      "hands_mode" => hands_mode,
      "play_count" => play_count,
      "clear_count" => clear_count,
      "multi_count" => multi_count,
      "clear_flag" => clear_flag,
      "slow_count" => slow_count,
      "fast_count" => fast_count,
      "judge_count_miss" => judge_count_miss,
      "judge_count_good" => judge_count_good,
      "judge_count_just" => judge_count_just,
      "judge_count_super_just" => judge_count_super_just,
      "judge_count_near" => judge_count_near,
      "judge_percent_max_count_long_miss" => judge_percent_max_count_long_miss,
      "judge_percent_max_count_long_good" => judge_percent_max_count_long_good,
      "judge_percent_max_count_long_just" => judge_percent_max_count_long_just,
      "judge_percent_max_count_long_super_just" => judge_percent_max_count_long_super_just,
      "judge_percent_max_count_long_near" => judge_percent_max_count_long_near,
      "judge_percent_max_count_trill_miss" => judge_percent_max_count_trill_miss,
      "judge_percent_max_count_trill_good" => judge_percent_max_count_trill_good,
      "judge_percent_max_count_trill_just" => judge_percent_max_count_trill_just,
      "judge_percent_max_count_trill_super_just" => judge_percent_max_count_trill_super_just,
      "judge_percent_max_count_trill_near" => judge_percent_max_count_trill_near,
      "note_num_normal" => note_num_normal,
      "note_num_long" => note_num_long,
      "note_num_glissando" => note_num_glissando,
      "note_num_trill" => note_num_trill,
      "note_success_rate_normal" => note_success_rate_normal,
      "note_success_rate_long" => note_success_rate_long,
      "note_success_rate_glissando" => note_success_rate_glissando,
      "note_success_rate_trill" => note_success_rate_trill,
      "best_score" => best_score
    })

    best =
      DB.get("nostalgia_scores_best", %{
        "nostalgia_id" => nostalgia_id,
        "music_index" => music_index,
        "sheet_type" => sheet_type
      }) || %{}

    best_score_data = %{
      "game_version" => game_version,
      "nostalgia_id" => nostalgia_id,
      "music_index" => music_index,
      "sheet_type" => sheet_type,
      "score" => max(score, Map.get(best, "score", score)),
      "play_count" => play_count,
      "clear_count" => clear_count,
      "multi_count" => multi_count,
      "clear_flag" => max(clear_flag, Map.get(best, "clear_flag", clear_flag)),
      "hands_mode" => max(hands_mode, Map.get(best, "hands_mode", hands_mode)),
      "grade" => max(grade, Map.get(best, "grade", grade))
    }

    DB.upsert("nostalgia_scores_best", best_score_data, %{
      "nostalgia_id" => nostalgia_id,
      "music_index" => music_index,
      "sheet_type" => sheet_type
    })

    response = E.e("response", E.e("set_stage_result", E.e("player")))

    Core.send_response(conn, info, response)
  end

  def op3_player_set_total_result(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    root = Core.module_node(info)

    refid = root |> XNode.child("refid") |> text()
    profile = get_profile(refid)
    _nostalgia_id = profile["nostalgia_id"]
    game_profile = get_in(profile || %{}, ["version", to_string(game_version)]) || %{}

    game_profile =
      Enum.reduce(@last_keys, game_profile, fn k, game_profile ->
        Map.put(game_profile, k, root |> XNode.child("last") |> XNode.child(k) |> text() |> int())
      end)

    game_profile =
      Enum.reduce(@travel_keys, game_profile, fn k, game_profile ->
        Map.put(
          game_profile,
          k,
          root |> XNode.child("travel") |> XNode.child(k) |> text() |> int()
        )
      end)

    extra_param = XNode.child(root, "extra_param")

    game_profile =
      extra_param
      |> XNode.children("param")
      |> Enum.reduce(game_profile, fn param, game_profile ->
        values = param |> XNode.child("params_array") |> XNode.text_ints()
        Map.put(game_profile, "param" <> XNode.attr(param, "type"), values)
      end)

    profile = put_in(profile, ["version", to_string(game_version)], game_profile)

    DB.upsert("nostalgia_profile", profile, %{"card" => refid})

    response = E.e("response", E.e("set_total_result", E.e("player")))

    Core.send_response(conn, info, response)
  end

  ## Helpers

  # E.e/2 with an empty list would emit a `__count="0"` value node; the Python
  # ElementMaker produces an empty container element instead.
  defp non_empty([]), do: nil
  defp non_empty(list), do: list

  defp text(%XNode{text: text}), do: text

  defp int(text) when is_binary(text), do: text |> String.trim() |> String.to_integer()
end
