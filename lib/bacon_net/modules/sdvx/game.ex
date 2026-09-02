defmodule BaconNet.Modules.Sdvx.Game do
  @moduledoc "Port of modules/sdvx/game.py."

  alias BaconNet.{CP932, Core, DB, E, Kbinxml, Scores, XNode}

  def routes do
    %{
      prefix: "/local2",
      tag: "local2",
      handlers: [
        {"game", "sv{ver}_common", :game_sv_common},
        {"game", "sv{ver}_new", :game_sv_new},
        {"game", "sv{ver}_load", :game_sv_load},
        {"game", "sv{ver}_load_m", :game_sv_load_m},
        {"game", "sv{ver}_save", :game_sv_save},
        {"game", "sv{ver}_save_m", :game_sv_save_m},
        {"game", "sv{ver}_hiscore", :game_sv_hiscore},
        {"game", "sv{ver}_lounge", :game_sv_lounge},
        {"game", "sv{ver}_shop", :game_sv_shop},
        {"game", "sv{ver}_load_r", :game_sv_load_r},
        {"game", "sv{ver}_frozen", :game_sv_frozen},
        {"game", "sv{ver}_save_e", :game_sv_save_e},
        {"game", "sv{ver}_save_mega", :game_sv_save_mega},
        {"game", "sv{ver}_play_e", :game_sv_play_e},
        {"game", "sv{ver}_play_s", :game_sv_play_s},
        {"game", "sv{ver}_entry_s", :game_sv_entry_s},
        {"game", "sv{ver}_entry_e", :game_sv_entry_e},
        {"game", "sv{ver}_log", :game_sv_log}
      ]
    }
  end

  @events [
    "DEMOGAME_PLAY",
    "MATCHING_MODE",
    "MATCHING_MODE_FREE_IP",
    "LEVEL_LIMIT_EASING",
    "ACHIEVEMENT_ENABLE",
    "APICAGACHADRAW\t30",
    "VOLFORCE_ENABLE",
    "AKANAME_ENABLE",
    "PAUSE_ONLINEUPDATE",
    "CONTINUATION",
    "TENKAICHI_MODE",
    "QC_MODE",
    "KAC_MODE",
    # "APPEAL_CARD_GEN_PRICE\t100",
    # "APPEAL_CARD_GEN_NEW_PRICE\t200",
    # "APPEAL_CARD_UNLOCK\t0,20170914,0,20171014,0,20171116,0,20180201,0,20180607,0,20181206,0,20200326,0,20200611,4,10140732,6,10150431",
    "FAVORITE_APPEALCARD_MAX\t200",
    "FAVORITE_MUSIC_MAX\t200",
    "EVENTDATE_APRILFOOL",
    "KONAMI_50TH_LOGO",
    "OMEGA_ARS_ENABLE",
    "DISABLE_MONITOR_ID_CHECK",
    "SKILL_ANALYZER_ABLE",
    "BLASTER_ABLE",
    "STANDARD_UNLOCK_ENABLE",
    "PLAYERJUDGEADJ_ENABLE",
    "MIXID_INPUT_ENABLE",
    "EVENTDATE_ONIGO",
    "EVENTDATE_GOTT",
    "GENERATOR_ABLE",
    "CREW_SELECT_ABLE",
    "PREMIUM_TIME_ENABLE",
    "OMEGA_ENABLE\t1,2,3,4,5,6,7,8,9",
    "HEXA_ENABLE\t1,2,3,4,5,6,7,8,9,10,11",
    "HEXA_OVERDRIVE_ENABLE\t8",
    "MEGAMIX_ENABLE",
    "VALGENE_ENABLE",
    "ARENA_ENABLE",
    "ARENA_LOCAL_TO_ONLINE_ENABLE",
    "ARENA_ALTER_MODE_WINDOW_ENABLE",
    "ARENA_PASS_MATCH_WINDOW_ENABLE",
    "DEMOLOOP_PASELI_FESTIVAL_2022",
    "DISABLED_MUSIC_IN_ARENA_ONLINE",
    "ARENA_VOTE_MODE_ENABLE",
    "DISP_PASELI_BANNER",
    "S_PUC_EFFECT_ENABLE",
    "SUPER_RANDOM_ACTIVE",
    "PLAYER_RADAR_ENABLE",
    "APRIL_RAINBOW_LINE_ACTIVE",
    "USE_CUDA_VIDEO_PRESENTER",
    "CHARACTER_IGNORE_DISABLE\t122,123,131,139,140,143,149,160,162,163,164,167,170,174",
    "STAMP_IGNORE_DISABLE\t273~312,773~820,993~1032,1245~1284,1469~1508,1585~1632,1633~1672,1737~1776,1777~1816,1897~1936",
    "SUBBG_IGNORE_DISABLE\t166~185,281~346,369~381,419~438,464~482,515~552,595~616,660~673,714~727"
  ]

  @difficulties [
    {0, "novice"},
    {1, "advanced"},
    {2, "exhaust"},
    {3, "infinite"},
    {4, "maximum"},
    {5, "ultimate"}
  ]

  @save_nodes [
    "appeal_id",
    "skill_level",
    "skill_base_id",
    "skill_name_id",
    "skill_type",
    "earned_gamecoin_packet",
    "earned_gamecoin_block",
    "earned_blaster_energy",
    "earned_extrack_energy",
    "hispeed",
    "lanespeed",
    "gauge_option",
    "ars_option",
    "notes_option",
    "early_late_disp",
    "draw_adjust",
    "eff_c_left",
    "eff_c_right",
    "music_id",
    "music_type",
    "sort_type",
    "narrow_down",
    "headphone",
    "start_option"
  ]

  defp get_profile(cid) do
    DB.get("sdvx_profile", %{"card" => cid})
  end

  defp get_game_profile(cid, game_version) do
    profile = get_profile(cid)
    get_in(profile || %{}, ["version", to_string(game_version)])
  end

  defp get_id_from_profile(cid) do
    profile = DB.get("sdvx_profile", %{"card" => cid})

    djid = Integer.to_string(profile["sdvx_id"]) |> String.pad_leading(8, "0")
    djid_split = binary_part(djid, 0, 4) <> "-" <> binary_part(djid, 4, 4)

    {profile["sdvx_id"], djid_split}
  end

  def game_sv_common(conn, _ver) do
    {info, conn} = Core.process_request(conn)

    unlock =
      case load_xml(["modules/sdvx/music_db.xml", "music_db.xml"], :shift_jisx0213) do
        nil ->
          []

        mdb ->
          Enum.flat_map(mdb.children, fn entry ->
            mid = XNode.attr(entry, "id")

            Enum.flat_map(@difficulties, fn {k, difficulty} ->
              case entry |> XNode.child("difficulty") |> XNode.child(difficulty) do
                nil ->
                  []

                d ->
                  limit = d |> XNode.child("limited") |> text() |> int()

                  if limit != 3 do
                    [[mid, k]]
                  else
                    []
                  end
              end
            end)
          end)
      end

    unlock =
      if unlock == [] do
        for i <- 0..2399, j <- 0..4, do: [i, j]
      else
        unlock
      end

    response =
      E.e(
        "response",
        E.e("game", [
          E.e(
            "event",
            for s <- @events do
              E.e("info", E.e("event_id", s, __type: "str"))
            end
          ),
          E.e(
            "music_limited",
            for [mid, k] <- unlock do
              E.e("info", [
                E.e("music_id", mid, __type: "s32"),
                E.e("music_type", k, __type: "u8"),
                E.e("limited", 3, __type: "u8")
              ])
            end
          )
        ])
      )

    Core.send_response(conn, info, response)
  end

  def game_sv_new(conn, _ver) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    root = Core.module_node(info)

    dataid = root |> XNode.child("dataid") |> text()
    _cardno = root |> XNode.child("cardno") |> text()
    name = root |> XNode.child("name") |> text()

    all_profiles_for_card =
      DB.get("sdvx_profile", %{"card" => dataid}) || %{"card" => dataid, "version" => %{}}

    all_profiles_for_card =
      if Map.has_key?(all_profiles_for_card, "sdvx_id") do
        all_profiles_for_card
      else
        Map.put(all_profiles_for_card, "sdvx_id", :rand.uniform(90_000_000) + 9_999_999)
      end

    version = %{
      "game_version" => game_version,
      "name" => name,
      "appeal_id" => 0,
      "skill_level" => 0,
      "skill_base_id" => 0,
      "skill_name_id" => 0,
      "earned_gamecoin_packet" => 0,
      "earned_gamecoin_block" => 0,
      "earned_blaster_energy" => 0,
      "earned_extrack_energy" => 0,
      "used_packet_booster" => 0,
      "used_block_booster" => 0,
      "hispeed" => 0,
      "lanespeed" => 0,
      "gauge_option" => 0,
      "ars_option" => 0,
      "notes_option" => 0,
      "early_late_disp" => 0,
      "draw_adjust" => 0,
      "eff_c_left" => 0,
      "eff_c_right" => 1,
      "music_id" => 0,
      "music_type" => 0,
      "sort_type" => 0,
      "narrow_down" => 0,
      "headphone" => 1,
      "print_count" => 0,
      "start_option" => 0,
      "bgm" => 0,
      "submonitor" => 0,
      "nemsys" => 0,
      "stampA" => 0,
      "stampB" => 0,
      "stampC" => 0,
      "stampD" => 0,
      "items" => [],
      "params" => []
    }

    all_profiles_for_card =
      put_in(all_profiles_for_card, ["version", to_string(game_version)], version)

    DB.upsert("sdvx_profile", all_profiles_for_card, %{"card" => dataid})

    response =
      E.e(
        "response",
        E.e(
          "game",
          E.e("result", 0, __type: "u8")
        )
      )

    Core.send_response(conn, info, response)
  end

  def game_sv_load(conn, _ver) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    dataid = Core.module_node(info) |> XNode.child("dataid") |> text()
    profile = get_game_profile(dataid, game_version)

    response =
      if profile != nil and profile != %{} do
        {_djid, djid_split} = get_id_from_profile(dataid)

        unlock =
          for(i <- 0..300, do: [i, 11, 15]) ++
            for(i <- 0..6000, do: [i, 1, 1]) ++
            [[599, 4, 10]] ++
            profile["items"]

        customize =
          [
            [
              2,
              2,
              [
                profile["bgm"],
                profile["submonitor"],
                profile["nemsys"],
                profile["stampA"],
                profile["stampB"],
                profile["stampC"],
                profile["stampD"]
              ]
            ]
          ] ++ profile["params"]

        game_children =
          [
            E.e("result", 0, __type: "u8"),
            E.e("name", profile["name"], __type: "str"),
            E.e("code", djid_split, __type: "str"),
            E.e("sdvx_id", djid_split, __type: "str"),
            E.e("appeal_id", profile["appeal_id"], __type: "u16"),
            E.e("skill_level", profile["skill_level"], __type: "s16"),
            E.e("skill_base_id", profile["skill_base_id"], __type: "s16"),
            E.e("skill_name_id", profile["skill_name_id"], __type: "s16"),
            E.e("gamecoin_packet", profile["earned_gamecoin_packet"], __type: "u32"),
            E.e("gamecoin_block", profile["earned_gamecoin_block"], __type: "u32"),
            E.e("blaster_energy", profile["earned_blaster_energy"], __type: "u32"),
            E.e("blaster_count", 9999, __type: "u32"),
            E.e("extrack_energy", profile["earned_extrack_energy"], __type: "u16"),
            E.e("play_count", 1001, __type: "u32"),
            E.e("day_count", 301, __type: "u32"),
            E.e("today_count", 21, __type: "u32"),
            E.e("play_chain", 31, __type: "u32"),
            E.e("max_play_chain", 31, __type: "u32"),
            E.e("week_count", 9, __type: "u32"),
            E.e("week_play_count", 101, __type: "u32"),
            E.e("week_chain", 31, __type: "u32"),
            E.e("max_week_chain", 1001, __type: "u32"),
            E.e("creator_id", 1, __type: "u32"),
            E.e("eaappli", E.e("relation", 1, __type: "s8")),
            E.e("ea_shop", [
              E.e("blaster_pass_enable", 1, __type: "bool"),
              E.e("blaster_pass_limit_date", 1_605_871_200, __type: "u64")
            ]),
            E.e("kac_id", profile["name"], __type: "str"),
            E.e("block_no", 0, __type: "s32"),
            E.e(
              "volte_factory",
              for s <- 1..998 do
                E.e("info", [
                  E.e("goods_id", s, __type: "s32"),
                  E.e("status", 1, __type: "s32")
                ])
              end
            )
          ] ++
            for s <- 0..98 do
              E.e("campaign", [
                E.e("campaign_id", s, __type: "s32"),
                E.e("jackpot_flg", 1, __type: "bool")
              ])
            end ++
            [
              E.e("cloud", E.e("relation", 1, __type: "s8")),
              E.e(
                "something",
                for [ranking_id, value] <- [[1_402, 20_000]] do
                  E.e("info", [
                    E.e("ranking_id", ranking_id, __type: "s32"),
                    E.e("value", value, __type: "s64")
                  ])
                end
              ),
              E.e(
                "festival",
                [
                  E.e("fes_id", 1, __type: "s32"),
                  E.e("live_energy", 1_000_000, __type: "s32")
                ] ++
                  for s <- 1..5 do
                    E.e("bonus", [
                      E.e("energy_type", s, __type: "s32"),
                      E.e("live_energy", 1_000_000, __type: "s32")
                    ])
                  end
              ),
              E.e("valgene_ticket", [
                E.e("ticket_num", 0, __type: "s32"),
                E.e("limit_date", 1_605_871_200, __type: "u64")
              ]),
              E.e("arena", [
                E.e("last_play_season", 0, __type: "s32"),
                E.e("rank_point", 0, __type: "s32"),
                E.e("shop_point", 0, __type: "s32"),
                E.e("ultimate_rate", 0, __type: "s32"),
                E.e("ultimate_rank_num", 0, __type: "s32"),
                E.e("rank_play_cnt", 0, __type: "s32"),
                E.e("ultimate_play_cnt", 0, __type: "s32")
              ]),
              E.e("hispeed", profile["hispeed"], __type: "s32"),
              E.e("lanespeed", profile["lanespeed"], __type: "u32"),
              E.e("gauge_option", profile["gauge_option"], __type: "u8"),
              E.e("ars_option", profile["ars_option"], __type: "u8"),
              E.e("notes_option", profile["notes_option"], __type: "u8"),
              E.e("early_late_disp", profile["early_late_disp"], __type: "u8"),
              E.e("draw_adjust", profile["draw_adjust"], __type: "s32"),
              E.e("eff_c_left", profile["eff_c_left"], __type: "u8"),
              E.e("eff_c_right", profile["eff_c_right"], __type: "u8"),
              E.e("last_music_id", profile["music_id"], __type: "s32"),
              E.e("last_music_type", profile["music_type"], __type: "u8"),
              E.e("sort_type", profile["sort_type"], __type: "u8"),
              E.e("narrow_down", profile["narrow_down"], __type: "u8"),
              E.e("headphone", profile["headphone"], __type: "u8"),
              E.e(
                "item",
                for [id, type, param] <- unlock do
                  E.e("info", [
                    E.e("id", id, __type: "u32"),
                    E.e("type", type, __type: "u8"),
                    E.e("param", param, __type: "u32")
                  ])
                end
              ),
              E.e(
                "param",
                for [type, id, param] <- customize do
                  E.e("info", [
                    E.e("type", type, __type: "s32"),
                    E.e("id", id, __type: "s32"),
                    E.e("param", param, __type: "s32", __count: length(param))
                  ])
                end
              )
            ]

        E.e("response", E.e("game", game_children))
      else
        E.e(
          "response",
          E.e(
            "game",
            E.e("result", 1, __type: "u8")
          )
        )
      end

    Core.send_response(conn, info, response)
  end

  def game_sv_load_m(conn, ver) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    dataid = Core.module_node(info) |> XNode.child("refid") |> text()
    _profile = get_game_profile(dataid, game_version)
    {djid, _djid_split} = get_id_from_profile(dataid)

    best_scores =
      for record <-
            DB.search("sdvx_scores_best", %{
              "game_version" => game_version,
              "sdvx_id" => djid
            }) do
        scores = [
          record["music_id"],
          record["music_type"],
          record["score"],
          record["exscore"],
          record["clear_type"],
          record["score_grade"],
          0,
          0,
          record["btn_rate"],
          record["long_rate"],
          record["vol_rate"],
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0
        ]

        if String.to_integer(ver) == 7 do
          scores ++ [0, 0, 0, 0, 0]
        else
          scores
        end
      end

    music_infos =
      for x <- best_scores do
        E.e(
          "info",
          E.e("param", x, __type: "u32")
        )
      end

    response =
      E.e(
        "response",
        E.e(
          "game",
          E.e("music", non_empty(music_infos))
        )
      )

    Core.send_response(conn, info, response)
  end

  def game_sv_save(conn, _ver) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    root = Core.module_node(info)
    dataid = root |> XNode.child("refid") |> text()

    profile = get_profile(dataid)
    game_profile = get_in(profile || %{}, ["version", to_string(game_version)]) || %{}

    game_profile =
      Map.put(game_profile, "appeal_id", root |> XNode.child("appeal_id") |> text() |> int())

    game_profile =
      Enum.reduce(@save_nodes, game_profile, fn node, game_profile ->
        case XNode.child(root, node) do
          nil ->
            game_profile

          n ->
            value = int(n.text)

            if String.starts_with?(node, "earned_") do
              Map.update!(game_profile, node, &(&1 + value))
            else
              Map.put(game_profile, node, value)
            end
        end
      end)

    ea_shop = XNode.child(root, "ea_shop")

    game_profile =
      Map.put(
        game_profile,
        "used_packet_booster",
        ea_shop.children |> Enum.at(0) |> text() |> int()
      )

    game_profile =
      Map.put(
        game_profile,
        "used_block_booster",
        ea_shop.children |> Enum.at(1) |> text() |> int()
      )

    game_profile =
      Map.put(
        game_profile,
        "print_count",
        root |> XNode.child("print") |> first_child() |> text() |> int()
      )

    # item fix (copied from drs, this is regarded)
    items =
      Enum.reduce(game_profile["items"], {[], %{}}, fn [old_t, old_i, old_p], acc ->
        nested_put(acc, to_string(old_t), to_string(old_i), to_string(old_p))
      end)

    items =
      root
      |> XNode.child("item")
      |> children()
      |> Enum.reduce(items, fn item_info, acc ->
        t = item_info |> XNode.child("id") |> text()
        i = item_info |> XNode.child("type") |> text()
        p = item_info |> XNode.child("param") |> text()

        nested_put(acc, t, i, p)
      end)

    items_list =
      items
      |> nested_to_list()
      |> Enum.map(fn {t, i, p} ->
        [String.to_integer(t), String.to_integer(i), String.to_integer(p)]
      end)

    game_profile = Map.put(game_profile, "items", items_list)

    # param fix (copied from drs, this is regarded)
    params =
      Enum.reduce(game_profile["params"], {[], %{}}, fn [old_t, old_i, old_p], acc ->
        nested_put(acc, to_string(old_t), to_string(old_i), old_p)
      end)

    params =
      root
      |> XNode.child("param")
      |> children()
      |> Enum.reduce(params, fn param_info, acc ->
        t = param_info |> XNode.child("type") |> text()
        i = param_info |> XNode.child("id") |> text()
        p = param_info |> XNode.child("param") |> XNode.text_ints()

        nested_put(acc, t, i, p)
      end)

    params_list =
      params
      |> nested_to_list()
      |> Enum.map(fn {t, i, p} -> [String.to_integer(t), String.to_integer(i), p] end)

    game_profile = Map.put(game_profile, "params", params_list)

    profile = put_in(profile, ["version", to_string(game_version)], game_profile)

    DB.upsert("sdvx_profile", profile, %{"card" => dataid})

    response =
      E.e(
        "response",
        E.e("game")
      )

    Core.send_response(conn, info, response)
  end

  def game_sv_save_m(conn, _ver) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    timestamp = :os.system_time(:millisecond) / 1000

    root = Core.module_node(info)

    dataid = root |> XNode.child("dataid") |> text()
    profile = get_game_profile(dataid, game_version)
    {djid, _djid_split} = get_id_from_profile(dataid)

    track = XNode.child(root, "track")
    play_id = track |> XNode.child("play_id") |> text() |> int()
    music_id = track |> XNode.child("music_id") |> text() |> int()
    music_type = track |> XNode.child("music_type") |> text() |> int()
    score = track |> XNode.child("score") |> text() |> int()
    exscore = track |> XNode.child("exscore") |> text() |> int()
    clear_type = track |> XNode.child("clear_type") |> text() |> int()
    score_grade = track |> XNode.child("score_grade") |> text() |> int()
    max_chain = track |> XNode.child("max_chain") |> text() |> int()
    just = track |> XNode.child("just") |> text() |> int()
    critical = track |> XNode.child("critical") |> text() |> int()
    near = track |> XNode.child("near") |> text() |> int()
    error = track |> XNode.child("error") |> text() |> int()
    effective_rate = track |> XNode.child("effective_rate") |> text() |> int()
    btn_rate = track |> XNode.child("btn_rate") |> text() |> int()
    long_rate = track |> XNode.child("long_rate") |> text() |> int()
    vol_rate = track |> XNode.child("vol_rate") |> text() |> int()
    mode = track |> XNode.child("mode") |> text() |> int()
    gauge_type = track |> XNode.child("gauge_type") |> text() |> int()
    notes_option = track |> XNode.child("notes_option") |> text() |> int()
    online_num = track |> XNode.child("online_num") |> text() |> int()
    local_num = track |> XNode.child("local_num") |> text() |> int()
    challenge_type = track |> XNode.child("challenge_type") |> text() |> int()
    retry_cnt = track |> XNode.child("retry_cnt") |> text() |> int()
    judge = track |> XNode.child("judge") |> XNode.text_ints()

    attempt_doc = %{
      "timestamp" => timestamp,
      "game_version" => game_version,
      "sdvx_id" => djid,
      "play_id" => play_id,
      "music_id" => music_id,
      "music_type" => music_type,
      "score" => score,
      "exscore" => exscore,
      "clear_type" => clear_type,
      "score_grade" => score_grade,
      "max_chain" => max_chain,
      "just" => just,
      "critical" => critical,
      "near" => near,
      "error" => error,
      "effective_rate" => effective_rate,
      "btn_rate" => btn_rate,
      "long_rate" => long_rate,
      "vol_rate" => vol_rate,
      "mode" => mode,
      "gauge_type" => gauge_type,
      "notes_option" => notes_option,
      "online_num" => online_num,
      "local_num" => local_num,
      "challenge_type" => challenge_type,
      "retry_cnt" => retry_cnt,
      "judge" => judge
    }

    # The best key includes the game version, carried in play_style.
    case Scores.record_attempt(%{
           game: "sdvx",
           version: game_version,
           player: to_string(djid),
           song: music_id,
           chart: music_type,
           play_style: to_string(game_version),
           score: score,
           clear: clear_type,
           miss: nil,
           payload: %{
             "exscore" => exscore,
             "score_grade" => score_grade,
             "btn_rate" => btn_rate,
             "long_rate" => long_rate,
             "vol_rate" => vol_rate,
             "game_version" => game_version,
             "name" => profile["name"]
           },
           attempt: attempt_doc,
           stats: %{clear: clear_type >= 2, fc: clear_type >= 4},
           merge: Scores.Merge.spec("sdvx"),
           idempotency: %{
             key: Scores.derive_key("sdvx", "#{info.module}.#{info.method}", djid, info.text),
             scope: "#{info.module}.#{info.method}",
             payload_hash: Scores.hash_payload(info.text)
           },
           dual_write: fn _recorded ->
             dual_write_save_m(
               attempt_doc,
               game_version,
               djid,
               profile["name"],
               music_id,
               music_type,
               score,
               exscore,
               clear_type,
               score_grade,
               btn_rate,
               long_rate,
               vol_rate
             )
           end
         }) do
      {:ok, _recorded} ->
        response =
          E.e(
            "response",
            E.e("game")
          )

        Core.send_response(conn, info, response)

      {:error, _reason} ->
        Core.reject_request(conn, info)
    end
  end

  # Project the recorded play into the legacy document tables, in the same
  # transaction. sdvx api/game read paths still use those; the relational
  # best_scores row lock serializes writers per player+chart.
  defp dual_write_save_m(
         attempt_doc,
         game_version,
         djid,
         name,
         music_id,
         music_type,
         score,
         exscore,
         clear_type,
         score_grade,
         btn_rate,
         long_rate,
         vol_rate
       ) do
    DB.insert("sdvx_scores", attempt_doc)

    best_conds = %{
      "sdvx_id" => djid,
      "game_version" => game_version,
      "music_id" => music_id,
      "music_type" => music_type
    }

    best = DB.get("sdvx_scores_best", best_conds) || %{}

    best_score_data = %{
      "game_version" => game_version,
      "sdvx_id" => djid,
      "name" => name,
      "music_id" => music_id,
      "music_type" => music_type,
      "score" => max(score, Map.get(best, "score", score)),
      "exscore" => max(exscore, Map.get(best, "exscore", exscore)),
      "clear_type" => max(clear_type, Map.get(best, "clear_type", clear_type)),
      "score_grade" => max(score_grade, Map.get(best, "score_grade", score_grade)),
      "btn_rate" => max(btn_rate, Map.get(best, "btn_rate", btn_rate)),
      "long_rate" => max(long_rate, Map.get(best, "long_rate", long_rate)),
      "vol_rate" => max(vol_rate, Map.get(best, "vol_rate", vol_rate))
    }

    DB.upsert("sdvx_scores_best", best_score_data, best_conds)
  end

  def game_sv_hiscore(conn, _ver) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    best_scores =
      for record <- DB.search("sdvx_scores_best", %{"game_version" => game_version}) do
        [
          record["music_id"],
          record["music_type"],
          record["sdvx_id"],
          record["name"],
          record["score"]
        ]
      end

    ds =
      for [music_id, music_type, sdvx_id, name, score] <- best_scores do
        E.e("d", [
          E.e("id", music_id, __type: "u32"),
          E.e("ty", music_type, __type: "u32"),
          E.e("a_sq", sdvx_id, __type: "str"),
          E.e("a_nm", name, __type: "str"),
          E.e("a_sc", score, __type: "u32"),
          E.e("l_sq", sdvx_id, __type: "str"),
          E.e("l_nm", name, __type: "str"),
          E.e("l_sc", score, __type: "u32")
        ])
      end

    response =
      E.e(
        "response",
        E.e(
          "game",
          E.e("sc", non_empty(ds))
        )
      )

    Core.send_response(conn, info, response)
  end

  def game_sv_lounge(conn, _ver) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("game", E.e("interval", 30, __type: "u32"))
      )

    Core.send_response(conn, info, response)
  end

  def game_sv_shop(conn, _ver) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("game", E.e("nxt_time", 1000 * 5 * 60, __type: "u32"))
      )

    Core.send_response(conn, info, response)
  end

  def game_sv_load_r(conn, _ver) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("game")
      )

    Core.send_response(conn, info, response)
  end

  def game_sv_frozen(conn, _ver) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("game")
      )

    Core.send_response(conn, info, response)
  end

  def game_sv_save_e(conn, _ver) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("game")
      )

    Core.send_response(conn, info, response)
  end

  def game_sv_save_mega(conn, _ver) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("game")
      )

    Core.send_response(conn, info, response)
  end

  def game_sv_play_e(conn, _ver) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("game")
      )

    Core.send_response(conn, info, response)
  end

  def game_sv_play_s(conn, _ver) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("game")
      )

    Core.send_response(conn, info, response)
  end

  def game_sv_entry_s(conn, _ver) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("game")
      )

    Core.send_response(conn, info, response)
  end

  def game_sv_entry_e(conn, _ver) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("game")
      )

    Core.send_response(conn, info, response)
  end

  def game_sv_log(conn, _ver) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("game")
      )

    Core.send_response(conn, info, response)
  end

  ## Helpers

  # Parse the first existing file of `paths` as XML, decoding shift_jisx0213
  # through the cp932 table. Returns the root XNode, or nil when none of the
  # paths exist (mirrors the Python `for f in (...): if path.exists(f)` loop).
  defp load_xml(paths, encoding) do
    Enum.find_value(paths, fn f ->
      if File.exists?(f) do
        raw = File.read!(f)
        text = if encoding == :shift_jisx0213, do: CP932.decode(raw), else: raw
        Kbinxml.from_text(text).node
      end
    end)
  end

  # E.e/2 with an empty list would emit a `__count="0"` value node; the Python
  # ElementMaker produces an empty container element instead.
  defp non_empty([]), do: nil
  defp non_empty(list), do: list

  defp first_child(%XNode{children: [first | _]}), do: first

  defp children(%XNode{children: children}), do: children

  defp text(%XNode{text: text}), do: text

  defp int(text) when is_binary(text), do: text |> String.trim() |> String.to_integer()

  # Insertion-ordered nested string map {t => {i => p}}, mirroring the Python
  # dict-of-dicts used by the item/param "fix" loops: keys iterate in first
  # insertion order, values are overwritten in place. State is
  # {t_order, %{t => {i_order, %{i => p}}}}.
  defp nested_put({t_order, data}, t, i, p) do
    {t_order, {i_order, values}} =
      case Map.fetch(data, t) do
        :error -> {t_order ++ [t], {[], %{}}}
        {:ok, inner} -> {t_order, inner}
      end

    i_order = if Map.has_key?(values, i), do: i_order, else: i_order ++ [i]
    values = Map.put(values, i, p)

    {t_order, Map.put(data, t, {i_order, values})}
  end

  defp nested_to_list({t_order, data}) do
    Enum.flat_map(t_order, fn t ->
      {i_order, values} = Map.fetch!(data, t)

      Enum.map(i_order, fn i ->
        {t, i, Map.fetch!(values, i)}
      end)
    end)
  end
end
