defmodule BaconNet.Modules.Gitadora.Gameend do
  @moduledoc "Port of modules/gitadora/gameend.py."

  alias BaconNet.{Core, DB, E, XNode}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"{ver}_gameend", "regist", :gitadora_gameend_regist}
      ]
    }
  end

  defp get_profile(cid) do
    DB.get("gitadora_profile", %{"card" => cid})
  end

  def gitadora_gameend_regist(conn, ver) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version
    spec = info.spec

    g =
      cond do
        spec in ["A", "C"] -> "guitarfreaks"
        spec in ["B", "D"] -> "drummania"
      end

    root = Core.module_node(info)

    players = XNode.children(root, "player")

    no =
      Enum.reduce(players, nil, fn player, _no ->
        no = XNode.attr_int(player, "no")

        if XNode.attr(player, "card") == "use" do
          save_player(root, player, g, game_version)
        end

        no
      end)

    response =
      E.e(
        "response",
        E.e("#{ver}_gameend", [
          E.e("gamemode", mode: "game_mode"),
          E.e(
            "player",
            [
              E.e("skill", [
                E.e("rank", 1, __type: "s32"),
                E.e("total_nr", 1, __type: "s32")
              ]),
              E.e("all_skill", [
                E.e("rank", 1, __type: "s32"),
                E.e("total_nr", 1, __type: "s32")
              ])
            ],
            no: no,
            state: 0
          )
        ])
      )

    Core.send_response(conn, info, response)
  end

  defp save_player(root, player, g, game_version) do
    dataid = player |> XNode.child("refid") |> Map.get(:text)
    profile = get_profile(dataid)
    gitadora_id = profile["gitadora_id"]
    game_profile = get_in(profile, ["version", to_string(game_version)]) || %{}

    game_profile =
      put_game(
        game_profile,
        g,
        "customdata_playstyle",
        child_ints(player, ["customdata", "playstyle"])
      )

    game_profile =
      put_game(game_profile, g, "customdata_custom", child_ints(player, ["customdata", "custom"]))

    game_profile =
      Enum.reduce(
        [
          "cabid",
          "play",
          "playtime",
          "playterm",
          "session_cnt",
          "matching_num",
          "extra_stage",
          "extra_play",
          "extra_clear",
          "encore_play",
          "encore_clear",
          "pencore_play",
          "pencore_clear",
          "max_clear_diff",
          "max_full_diff",
          "max_exce_diff",
          "clear_num",
          "full_num",
          "exce_num",
          "no_num",
          "e_num",
          "d_num",
          "c_num",
          "b_num",
          "a_num",
          "s_num",
          "ss_num",
          "last_category",
          "last_musicid",
          "last_seq",
          "disp_level"
        ],
        game_profile,
        fn k, gp -> put_game(gp, g, "playinfo_" <> k, child_int(player, ["playinfo", k])) end
      )

    game_profile =
      put_game(game_profile, g, "tutorial_progress", child_int(player, ["tutorial", "progress"]))

    game_profile =
      put_game(
        game_profile,
        g,
        "tutorial_disp_state",
        child_int(player, ["tutorial", "disp_state"])
      )

    game_profile =
      put_game(game_profile, g, "information", child_ints(player, ["information", "info"]))

    game_profile = put_game(game_profile, g, "reward", child_ints(player, ["reward", "status"]))

    game_profile =
      put_game(game_profile, g, "skilldata_skill", child_int(player, ["skilldata", "skill"]))

    game_profile =
      put_game(
        game_profile,
        g,
        "skilldata_allskill",
        child_int(player, ["skilldata", "all_skill"])
      )

    groove = [
      "extra_gauge",
      "encore_gauge",
      "encore_cnt",
      "encore_success"
    ]

    groove =
      if game_version > 6 do
        groove ++ ["unlock_point"]
      else
        groove
      end

    game_profile =
      Enum.reduce(groove, game_profile, fn k, gp ->
        put_game(gp, g, "groove_" <> k, child_int(player, ["groove", k]))
      end)

    record_max = [
      "skill",
      "all_skill",
      "clear_diff",
      "full_diff",
      "exce_diff",
      "clear_music_num",
      "full_music_num",
      "exce_music_num",
      "clear_seq_num"
    ]

    record_max =
      if game_version > 6 do
        record_max ++ ["classic_all_skill"]
      else
        record_max
      end

    game_profile =
      Enum.reduce(record_max, game_profile, fn k, gp ->
        put_game(gp, g, "record_max_" <> k, child_int(player, ["record", "max", k]))
      end)

    game_profile =
      Enum.reduce(
        [
          "diff_100_nr",
          "diff_150_nr",
          "diff_200_nr",
          "diff_250_nr",
          "diff_300_nr",
          "diff_350_nr",
          "diff_400_nr",
          "diff_450_nr",
          "diff_500_nr",
          "diff_550_nr",
          "diff_600_nr",
          "diff_650_nr",
          "diff_700_nr",
          "diff_750_nr",
          "diff_800_nr",
          "diff_850_nr",
          "diff_900_nr",
          "diff_950_nr"
        ],
        game_profile,
        fn k, gp -> put_game(gp, g, "record_" <> k, child_int(player, ["record", "diff", k])) end
      )

    game_profile =
      Enum.reduce(
        [
          "diff_100_clear",
          "diff_150_clear",
          "diff_200_clear",
          "diff_250_clear",
          "diff_300_clear",
          "diff_350_clear",
          "diff_400_clear",
          "diff_450_clear",
          "diff_500_clear",
          "diff_550_clear",
          "diff_600_clear",
          "diff_650_clear",
          "diff_700_clear",
          "diff_750_clear",
          "diff_800_clear",
          "diff_850_clear",
          "diff_900_clear",
          "diff_950_clear"
        ],
        game_profile,
        fn k, gp -> put_game(gp, g, "record_" <> k, child_ints(player, ["record", "diff", k])) end
      )

    game_profile =
      Enum.reduce(
        [
          "music_list_1",
          "music_list_2",
          "music_list_3"
        ],
        game_profile,
        fn k, gp ->
          put_game(gp, g, "favorite_" <> k, child_ints(player, ["favoritemusic", k]))
        end
      )

    version_key = to_string(game_version)

    profile =
      Map.put(
        profile,
        "version",
        Map.put(Map.get(profile, "version", %{}), version_key, game_profile)
      )

    DB.upsert("gitadora_profile", profile, %{"card" => dataid})

    stages = XNode.children(player, "stage")

    Enum.each(stages, fn s ->
      data_version = root |> XNode.child("data_version") |> Map.get(:text)
      timestamp = child_int(s, ["date_ms"])
      musicid = child_int(s, ["musicid"])
      seq = child_int(s, ["seq"])
      skill = child_int(s, ["skill"])
      new_skill = child_int(s, ["new_skill"])
      clear = child_int(s, ["clear"])
      auto_clear = child_int(s, ["auto_clear"])
      fullcombo = child_int(s, ["fullcombo"])
      excellent = child_int(s, ["excellent"])
      medal = child_int(s, ["medal"])
      perc = child_int(s, ["perc"])
      new_perc = child_int(s, ["new_perc"])
      rank = child_int(s, ["rank"])
      score = child_int(s, ["score"])
      combo = child_int(s, ["combo"])
      max_combo_perc = child_int(s, ["max_combo_perc"])
      flags = child_int(s, ["flags"])
      phrase_combo_perc = child_int(s, ["phrase_combo_perc"])
      perfect = child_int(s, ["perfect"])
      great = child_int(s, ["great"])
      good = child_int(s, ["good"])
      ok = child_int(s, ["ok"])
      miss = child_int(s, ["miss"])
      perfect_perc = child_int(s, ["perfect_perc"])
      great_perc = child_int(s, ["great_perc"])
      good_perc = child_int(s, ["good_perc"])
      ok_perc = child_int(s, ["ok_perc"])
      miss_perc = child_int(s, ["miss_perc"])
      meter = child_int(s, ["meter"])
      meter_prog = child_int(s, ["meter_prog"])
      before_meter = child_int(s, ["before_meter"])
      before_meter_prog = child_int(s, ["before_meter_prog"])
      is_new_meter = child_int(s, ["is_new_meter"])
      phrase_data_num = child_int(s, ["phrase_data_num"])
      phrase_addr = child_ints(s, ["phrase_addr"])
      phrase_type = child_ints(s, ["phrase_type"])
      phrase_status = child_ints(s, ["phrase_status"])
      phrase_end_addr = child_int(s, ["phrase_end_addr"])

      DB.insert("#{g}_scores", %{
        "timestamp" => timestamp,
        "game_version" => game_version,
        "gitadora_id" => gitadora_id,
        "data_version" => data_version,
        "musicid" => musicid,
        "seq" => seq,
        "skill" => skill,
        "new_skill" => new_skill,
        "clear" => clear,
        "auto_clear" => auto_clear,
        "fullcombo" => fullcombo,
        "excellent" => excellent,
        "medal" => medal,
        "perc" => perc,
        "new_perc" => new_perc,
        "rank" => rank,
        "score" => score,
        "combo" => combo,
        "max_combo_perc" => max_combo_perc,
        "flags" => flags,
        "phrase_combo_perc" => phrase_combo_perc,
        "perfect" => perfect,
        "great" => great,
        "good" => good,
        "ok" => ok,
        "miss" => miss,
        "perfect_perc" => perfect_perc,
        "great_perc" => great_perc,
        "good_perc" => good_perc,
        "ok_perc" => ok_perc,
        "miss_perc" => miss_perc,
        "meter" => meter,
        "meter_prog" => meter_prog,
        "before_meter" => before_meter,
        "before_meter_prog" => before_meter_prog,
        "is_new_meter" => is_new_meter,
        "phrase_data_num" => phrase_data_num,
        "phrase_addr" => phrase_addr,
        "phrase_type" => phrase_type,
        "phrase_status" => phrase_status,
        "phrase_end_addr" => phrase_end_addr
      })

      best_score =
        DB.get("#{g}_scores_best", %{
          "gitadora_id" => gitadora_id,
          "musicid" => musicid,
          "seq" => seq
        }) || %{}

      best_perc = Map.get(best_score, "perc", perc)

      best_score_data = %{
        "gitadora_id" => gitadora_id,
        "musicid" => musicid,
        "seq" => seq,
        "skill" => max(skill, Map.get(best_score, "skill", skill)),
        "clear" => max(clear, Map.get(best_score, "clear", clear)),
        "fullcombo" => max(fullcombo, Map.get(best_score, "fullcombo", fullcombo)),
        "excellent" => max(excellent, Map.get(best_score, "excellent", excellent)),
        "perc" => max(perc, Map.get(best_score, "perc", perc)),
        "rank" => max(rank, Map.get(best_score, "rank", rank)),
        "meter" =>
          if perc >= best_perc do
            meter
          else
            Map.get(best_score, "meter", meter)
          end,
        "meter_prog" =>
          if perc >= best_perc do
            meter_prog
          else
            Map.get(best_score, "meter_prog", meter_prog)
          end
      }

      DB.upsert("#{g}_scores_best", best_score_data, %{
        "gitadora_id" => gitadora_id,
        "musicid" => musicid,
        "seq" => seq
      })
    end)
  end

  defp put_game(game_profile, g, key, value) do
    Map.put(game_profile, g, Map.put(Map.get(game_profile, g, %{}), key, value))
  end

  defp child_int(node, path) do
    node |> get_in_path(path) |> Map.get(:text) |> String.to_integer()
  end

  defp child_ints(node, path) do
    node |> get_in_path(path) |> XNode.text_ints()
  end

  defp get_in_path(node, path) do
    Enum.reduce(path, node, fn tag, n -> XNode.child(n, tag) end)
  end
end
