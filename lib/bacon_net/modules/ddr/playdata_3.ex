defmodule BaconNet.Modules.Ddr.Playdata3 do
  @moduledoc "Port of modules/ddr/playdata_3.py (DDR World)."

  alias BaconNet.{Core, DB, E, State, XNode}

  def routes do
    %{
      prefix: "/local2",
      tag: "local2",
      handlers: [
        {"playdata_3", "musicdata_load", :playdata_3_musicdata_load},
        {"playdata_3", "playerdata_load", :playdata_3_playerdata_load},
        {"playdata_3", "rivaldata_load", :playdata_3_rivaldata_load},
        {"playdata_3", "playerdata_new", :playdata_3_playerdata_new},
        {"playdata_3", "playerdata_save", :playdata_3_playerdata_save},
        {"playdata_3", "ghostdata_load", :playdata_3_ghostdata_load},
        {"playdata_3", "mergeddata_load", :playdata_3_mergeddata_load}
      ]
    }
  end

  @load_settings [
    {"common",
     [
       {"dancername", "str"},
       {"area", "s32"},
       {"extrastar", "s32"},
       {"playcount", "s32"},
       {"weight", "s32"},
       {"today_cal", "u64"},
       {"is_disp_weight", "bool"},
       {"is_takeover", "bool"},
       {"pre_playable_num", "s32"},
       {"is_subscribed", "bool"},
       {"popup_subscribe_enable", "bool"},
       {"popup_subscribe_disable", "bool"}
     ]},
    {"option",
     [
       {"hispeed", "s32"},
       {"gauge", "s32"},
       {"fastslow", "s32"},
       {"guideline", "s32"},
       {"stepzone", "s32"},
       {"timing_disp", "s32"},
       {"visibility", "s32"},
       {"visible_time", "s32"},
       {"lane", "s32"},
       {"lane_hiddenpos", "s32"},
       {"lane_suddenpos", "s32"},
       {"lane_hidsudpos", "s32"},
       {"lane_filter", "s32"},
       {"scroll_direction", "s32"},
       {"scroll_moving", "s32"},
       {"arrow_priority", "s32"},
       {"arrow_placement", "s32"},
       {"arrow_color", "s32"},
       {"arrow_design", "s32"},
       {"cut_timing", "s32"},
       {"cut_freeze", "s32"},
       {"cut_jump", "s32"},
       {"speed_type", "s32"},
       {"real_speed", "s32"},
       {"lane_preview", "s32"},
       {"combo_priority", "s32"},
       {"judge_priority", "s32"},
       {"judge_position", "s32"},
       {"timing_music", "s32"}
     ]},
    {"lastplay",
     [
       {"mode", "s32"},
       {"folder", "s32"},
       {"mcode", "s32"},
       {"style", "s32"},
       {"difficulty", "s32"},
       {"window_main", "s32"},
       {"window_sub", "s32"},
       {"target", "s32"},
       {"tab_main", "s32"},
       {"tab_sub", "s32"},
       {"tab_main_graph_type", "s32"},
       {"tab_main_graph_disp", "s32"},
       {"tab_sub_graph_type", "s32"},
       {"tab_sub_graph_disp", "s32"}
     ]},
    {"filtersort",
     [
       {"title", "u64"},
       {"version", "u64"},
       {"genre", "u64"},
       {"bpm", "u64"},
       {"event", "u64"},
       {"level", "u64"},
       {"flare_rank", "u64"},
       {"clear_rank", "u64"},
       {"flare_skill_target", "u64"},
       {"rival_flare_skill", "u64"},
       {"rival_score_rank", "u64"},
       {"sort_type", "u64"},
       {"order_type", "s32"},
       {"is_quickmode", "bool"},
       {"cleartype", "u64"},
       {"difficulty", "u64"}
     ]},
    {"checkguide",
     [
       {"tips_basic", "u64"},
       {"tips_option", "u64"},
       {"tips_event", "u64"},
       {"tips_gimmick", "u64"},
       {"tips_advance", "u64"},
       {"guide_scene", "u64"}
     ]},
    {"brave",
     [
       {"last_braveid", "s32"},
       {"last_window_btn", "s32"}
     ]}
  ]

  @customize_settings %{
    # appeal_board
    "1" => %{"0" => -1},
    # character_left / character_right
    "2" => %{"1" => -1, "2" => -1},
    # game_bg_system / game_bg_play
    "3" => %{"1" => -1, "2" => -1},
    # lane_bg_single
    "4" => %{"0" => -1},
    # lane_bg_double
    "5" => %{"0" => -1},
    # lane_cover_single
    "6" => %{"0" => -1},
    # lane_cover_double
    "7" => %{"0" => -1},
    # song_vid
    "8" => %{"0" => -1}
  }

  @flares [
    {995_000, 10},
    {990_000, 9},
    {980_000, 8},
    {970_000, 7},
    {960_000, 6},
    {955_000, 5},
    {930_000, 4},
    {900_000, 3},
    {850_000, 2},
    {800_000, 1}
  ]

  def get_profile(cid), do: DB.get("ddr_profile", %{"card" => cid})

  def get_game_profile(cid, game_version) do
    profile = get_profile(cid)
    Map.get(profile["version"], to_string(game_version))
  end

  def playdata_3_musicdata_load(conn) do
    {info, conn} = Core.process_request(conn)
    {mdb, music_load} = mdb_cache()

    response =
      if mdb != %{} do
        E.e("response",
          E.e(
            "playdata_3",
            [
              E.e("result", 0, __type: "s32"),
              E.e("servertime", :os.system_time(:millisecond), __type: "u64")
            ] ++ for(s <- music_load, do: E.e("music", E.e("music_str", s, __type: "str")))
          )
        )
      else
        E.e("response",
          E.e("playdata_3", [
            E.e("result", 0, __type: "s32"),
            E.e("servertime", :os.system_time(:millisecond), __type: "u64"),
            E.e("music", E.e("music_str", "", __type: "str"))
          ])
        )
      end

    Core.send_response(conn, info, response)
  end

  def playdata_3_playerdata_load(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    data = Core.module_node(info) |> XNode.child("data")
    refid = find_text(data, "refid")

    default = "X0000000000000000000000000000000"

    {p, profile, scores_map, mcode_order} =
      if refid != default do
        p = get_profile(refid)

        if p != nil do
          ddr_id = Map.fetch!(p, "ddr_id")
          profile = get_game_profile(refid, game_version)
          {scores_map, mcode_order} = collect_scores(ddr_id)
          {p, profile, scores_map, mcode_order}
        else
          # Python: profile/all_scores stay unset here; the response build
          # then dies at E.ddrcode(p.get(...)) because p is None
          {p, nil, %{}, []}
        end
      else
        {%{}, %{}, %{}, []}
      end

    common_node =
      E.e("common", [
        E.e("ddrcode", Map.get(p, "ddr_id", 0), __type: "s32"),
        E.e("dancername", Map.get(profile, "common_dancername", ""), __type: "str"),
        E.e("is_new", profile == nil or profile == %{}, __type: "bool"),
        E.e("is_registering", 0, __type: "bool"),
        E.e("area", Map.get(profile, "common_area", 13), __type: "s32"),
        E.e("extrastar", Map.get(profile, "common_extrastar", 0), __type: "s32"),
        E.e("playcount", Map.get(profile, "common_playcount", 0), __type: "s32"),
        E.e("weight", Map.get(profile, "common_weight", 0), __type: "s32"),
        E.e("today_cal", Map.get(profile, "common_today_cal", 0), __type: "u64"),
        E.e("is_disp_weight", Map.get(profile, "common_is_disp_weight", 0), __type: "bool"),
        E.e("is_takeover", 0, __type: "bool"),
        E.e("pre_playable_num", 1, __type: "s32"),
        E.e("is_subscribed", 1, __type: "bool"),
        E.e("popup_subscribe_enable", 0, __type: "bool"),
        E.e("popup_subscribe_disable", 0, __type: "bool")
      ])

    settings_nodes =
      for {k, fields} <- @load_settings, k != "common" do
        E.e(k, for({v, type} <- fields, do: E.e(v, Map.get(profile, "#{k}_#{v}", 0), __type: type)))
      end

    rival_nodes =
      for i <- 1..3 do
        E.e("rival", [
          E.e("slot", i, __type: "s32"),
          E.e("rivalcode", Map.get(profile, "rival_#{i}_ddr_id", 0), __type: "s32")
        ])
      end

    score_nodes =
      for mcode <- mcode_order do
        diffs = Map.fetch!(scores_map, mcode)

        singles =
          for {difficulty, s} <- diffs, difficulty < 5,
              do: E.e("score_single", E.e("score_str", s, __type: "str"))

        doubles =
          for {difficulty, s} <- diffs, difficulty > 4,
              do: E.e("score_double", E.e("score_str", s, __type: "str"))

        E.e("score", [E.e("mcode", mcode, __type: "s32")] ++ singles ++ doubles)
      end

    event_nodes =
      [E.e("event", E.e("event_str", "1,101,0,0,14,0,0", __type: "str"))] ++
        for x <- 101..2//-1, x not in [4, 6, 7, 8, 14, 47, 90] do
          E.e("event", E.e("event_str", "#{x},9999,0,0,0,0,0", __type: "str"))
        end

    customize = Map.get(profile, "customize", %{})

    customize_nodes =
      for {c, patterns} <- customize, {pattern, key} <- patterns do
        E.e("customize", [
          E.e("category", c, __type: "s32"),
          E.e("key", key, __type: "s32"),
          E.e("pattern", pattern, __type: "s32")
        ])
      end

    response =
      E.e("response",
        E.e(
          "playdata_3",
          [
            E.e("result", 0, __type: "s32"),
            E.e("refid", refid, __type: "str"),
            E.e("gamesession", 1, __type: "s64"),
            E.e("servertime", :os.system_time(:millisecond), __type: "u64"),
            E.e("is_locked", 0, __type: "bool"),
            common_node
          ] ++ settings_nodes ++ rival_nodes ++ score_nodes ++ event_nodes ++ customize_nodes
        )
      )

    Core.send_response(conn, info, response)
  end

  def playdata_3_rivaldata_load(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    data = Core.module_node(info) |> XNode.child("data")
    loadflag = find_int(data, "loadkind")
    _country = find_text(data, "country")
    region = find_text(data, "region")
    _customercode = find_text(data, "customercode")
    _companycode = find_text(data, "companycode")
    _locationid = find_text(data, "locationid")
    pcbid = find_text(data, "pcbid")
    _targettime = find_text(data, "targettime")
    ddrcode = find_int(data, "ddrcode")

    scores =
      case loadflag do
        1 ->
          best_per_song(fn doc -> Map.get(doc, "ddr_id") != 0 end, game_version)

        2 ->
          best_per_song(
            fn doc -> Map.get(doc, "shoparea") == region and Map.get(doc, "ddr_id") != 0 end,
            game_version
          )

        3 ->
          best_per_song(
            fn doc -> Map.get(doc, "pcbid") == pcbid and Map.get(doc, "ddr_id") != 0 end,
            game_version
          )

        4 ->
          "ddr_scores_best"
          |> search_ordered(%{"ddr_id" => ddrcode})
          |> Enum.map(fn {_id, doc} -> doc end)

        # Python: scores stays unbound, NameError at `for r in scores`
        _ ->
          raise "name 'scores' is not defined"
      end

    names = build_names()

    rival_records =
      for r <- scores do
        {style, diffi} =
          if Map.fetch!(r, "difficulty") > 4,
            do: {1, Map.fetch!(r, "difficulty") - 4},
            else: {0, Map.fetch!(r, "difficulty")}

        name =
          case Map.get(names, Map.fetch!(r, "ddr_id")) do
            nil -> "UNKNOWN"
            entry -> Map.fetch!(entry, "name")
          end

        "#{Map.fetch!(r, "mcode")},#{style},#{diffi},0,#{name},0,0,1,#{Map.fetch!(r, "score")},#{Map.fetch!(r, "ghostid")}"
      end

    response =
      E.e("response",
        E.e(
          "playdata_3",
          [E.e("result", 0, __type: "s32")] ++
            for(s <- rival_records, do: E.e("record", E.e("record_str", s, __type: "str")))
        )
      )

    Core.send_response(conn, info, response)
  end

  def playdata_3_playerdata_new(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    data = Core.module_node(info) |> XNode.child("data")
    refid = find_text(data, "refid")

    all_profiles_for_card = DB.get("ddr_profile", %{"card" => refid})

    {ddr_id, all_profiles_for_card} =
      if !Map.has_key?(all_profiles_for_card, "ddr_id") do
        ddr_id = :rand.uniform(90_000_000) + 9_999_999
        {ddr_id, Map.put(all_profiles_for_card, "ddr_id", ddr_id)}
      else
        {Map.fetch!(all_profiles_for_card, "ddr_id"), all_profiles_for_card}
      end

    tmp = %{"game_version" => game_version}

    tmp =
      for {k, fields} <- @load_settings, {v, _type} <- fields, reduce: tmp do
        acc -> Map.put(acc, "#{k}_#{v}", 0)
      end

    tmp =
      tmp
      |> Map.put("rival_1_ddr_id", 0)
      |> Map.put("rival_2_ddr_id", 0)
      |> Map.put("rival_3_ddr_id", 0)
      |> Map.put("customize", @customize_settings)

    all_profiles_for_card = put_in(all_profiles_for_card, ["version", to_string(game_version)], tmp)

    DB.upsert("ddr_profile", all_profiles_for_card, %{"card" => refid})

    response =
      E.e("response",
        E.e("playdata_3", [
          E.e("result", 0, __type: "s32"),
          E.e("refid", refid, __type: "str"),
          E.e("ddrcode", ddr_id, __type: "s32"),
          E.e("istakeover", 0, __type: "bool")
        ])
      )

    Core.send_response(conn, info, response)
  end

  def playdata_3_playerdata_save(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    node = Core.module_node(info)
    retrycnt = find_int(node, "retrycnt")
    data = XNode.child(node, "data")

    refid = find_text(data, "refid")
    savekind = find_int(data, "savekind")

    profile = get_profile(refid)
    game_profile = get_game_profile(refid, game_version)

    response =
      if !String.starts_with?(refid, "X000") do
        cond do
          savekind in [1, 3] ->
            game_profile =
              for {k, fields} <- @load_settings, {v, _type} <- fields, reduce: game_profile do
                acc ->
                  profile_setting = data |> XNode.child(k) |> XNode.child(v)

                  cond do
                    v == "playcount" ->
                      Map.put(acc, "common_playcount", Map.fetch!(acc, "common_playcount") + 1)

                    String.starts_with?(v, "popup_subscribe") ->
                      Map.put(acc, "common_#{v}", "0")

                    profile_setting != nil ->
                      Map.put(acc, "#{k}_#{v}", Map.get(profile_setting, :text))

                    true ->
                      acc
                  end
              end

            game_profile = Map.put_new(game_profile, "customize", @customize_settings)
            version = Map.fetch!(profile, "version")

            profile =
              Map.put(profile, "version", Map.put(version, to_string(game_version), game_profile))

            DB.upsert("ddr_profile", profile, %{"card" => refid})

            E.e("response", E.e("playdata_3", E.e("result", 0, __type: "s32")))

          savekind == 2 and retrycnt == 0 ->
            timestamp = :os.system_time(:microsecond) / 1_000_000

            ddr_id = data |> XNode.child("common") |> XNode.child("ddrcode") |> text_int()
            pcbid = find_text(data, "pcbid")
            shoparea = find_text(data, "region")

            n = XNode.child(data, "result")

            playstyle = find_int(n, "style")
            mcode = find_int(n, "mcode")
            diffi = find_int(n, "difficulty")
            difficulty = if playstyle == 1, do: diffi + 4, else: diffi
            rank = find_int(n, "rank")
            lamp = find_int(n, "clearkind")
            score = find_int(n, "score")
            exscore = find_int(n, "exscore")
            maxcombo = find_int(n, "maxcombo")
            fastcount = find_int(n, "fastcount")
            slowcount = find_int(n, "slowcount")
            judge_marvelous = find_int(n, "judge_marv")
            judge_perfect = find_int(n, "judge_perf")
            judge_great = find_int(n, "judge_great")
            judge_good = find_int(n, "judge_good")
            judge_miss = find_int(n, "judge_miss")
            judge_ok = find_int(n, "judge_ok")
            judge_ng = find_int(n, "judge_ng")
            calorie = find_int(n, "calorie")
            ghostsize = find_int(n, "ghostsize")
            ghost = find_text(n, "ghost")
            flare_force = find_int(n, "flare_force")

            DB.insert("ddr_scores", %{
              "timestamp" => timestamp,
              "pcbid" => pcbid,
              "shoparea" => shoparea,
              "game_version" => game_version,
              "ddr_id" => ddr_id,
              "playstyle" => playstyle,
              "mcode" => mcode,
              "difficulty" => difficulty,
              "rank" => rank,
              "lamp" => lamp,
              "score" => score,
              "exscore" => exscore,
              "maxcombo" => maxcombo,
              "life" => -1,
              "fastcount" => fastcount,
              "slowcount" => slowcount,
              "judge_marvelous" => judge_marvelous,
              "judge_perfect" => judge_perfect,
              "judge_great" => judge_great,
              "judge_good" => judge_good,
              "judge_boo" => 0,
              "judge_miss" => judge_miss,
              "judge_ok" => judge_ok,
              "judge_ng" => judge_ng,
              "calorie" => calorie,
              "ghostsize" => ghostsize,
              "ghost" => ghost,
              "flare_force" => flare_force
            })

            conds = %{"ddr_id" => ddr_id, "mcode" => mcode, "difficulty" => difficulty}
            best = DB.get("ddr_scores_best", conds) || %{}

            best_score_data = %{
              "game_version" => game_version,
              "ddr_id" => ddr_id,
              "playstyle" => playstyle,
              "mcode" => mcode,
              "difficulty" => difficulty,
              "rank" => min(rank, Map.get(best, "rank", rank)),
              "lamp" => max(lamp, Map.get(best, "lamp", lamp)),
              "score" => max(score, Map.get(best, "score", score)),
              "exscore" => max(exscore, Map.get(best, "exscore", exscore)),
              "flare_force" => max(flare_force, Map.get(best, "flare_force", flare_force))
            }

            ghostid =
              "ddr_scores"
              |> search_ordered(fn doc ->
                Map.get(doc, "ddr_id") == ddr_id and Map.get(doc, "mcode") == mcode and
                  Map.get(doc, "difficulty") == difficulty and
                  Map.get(doc, "score") == max(score, Map.get(best, "score", score))
              end)
              |> List.first()

            best_score_data =
              case ghostid do
                {id, _doc} -> Map.put(best_score_data, "ghostid", id)
                nil -> Map.put(best_score_data, "ghostid", -1)
              end

            DB.upsert("ddr_scores_best", best_score_data, conds)

            E.e("response", E.e("playdata_3", E.e("result", 0, __type: "s32")))

          true ->
            E.e("response", E.e("playdata_3", E.e("result", 0, __type: "s32")))
        end
      else
        E.e("response", E.e("playdata_3", E.e("result", 1, __type: "s32")))
      end

    Core.send_response(conn, info, response)
  end

  def playdata_3_ghostdata_load(conn) do
    {info, conn} = Core.process_request(conn)

    data = Core.module_node(info) |> XNode.child("data")
    ghostid = find_int(data, "ghostid")

    record = get_doc_by_id("ddr_scores", ghostid)

    response =
      E.e("response",
        E.e("playdata_3", [
          E.e("result", 0, __type: "s32"),
          E.e("ghostsize", Map.fetch!(record, "ghostsize"), __type: "s32"),
          E.e("ghost", Map.fetch!(record, "ghost"), __type: "str")
        ])
      )

    Core.send_response(conn, info, response)
  end

  def playdata_3_mergeddata_load(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e("response",
        E.e("playdata_3", [
          E.e("result", 0, __type: "s32"),
          E.e("league_class", 0, __type: "s32"),
          E.e("is_advance_border_exceeded", 0, __type: "bool"),
          E.e("is_exists_subscribed_user", 0, __type: "bool")
        ])
      )

    Core.send_response(conn, info, response)
  end

  ## Helpers

  # mcode -> ordered [{difficulty, score_str}] pairs, mirroring the Python
  # dict-of-dicts accumulation (insertion order preserved)
  defp collect_scores(ddr_id) do
    "ddr_scores_best"
    |> search_ordered(%{"ddr_id" => ddr_id})
    |> Enum.reduce({%{}, []}, fn {_id, record}, {acc, order} ->
      mcode = Map.fetch!(record, "mcode")
      difficulty = to_int(Map.fetch!(record, "difficulty"))
      score = to_int(Map.fetch!(record, "score"))
      flare = to_int(Map.get(record, "flare_force", 0))

      flare =
        if flare in [-1, 0] do
          case Enum.find(@flares, fn {k, _v} -> score >= k end) do
            {_k, v} -> v
            nil -> flare
          end
        else
          flare
        end

      diff_str = if difficulty > 4, do: difficulty - 4, else: difficulty

      s =
        "#{diff_str},1,#{Map.fetch!(record, "rank")},#{Map.fetch!(record, "lamp")},#{score}," <>
          "#{Map.fetch!(record, "ghostid")},#{flare},#{flare},0"

      order = if Map.has_key?(acc, mcode), do: order, else: order ++ [mcode]
      diffs = put_diff(Map.get(acc, mcode, []), difficulty, s)
      {Map.put(acc, mcode, diffs), order}
    end)
  end

  # all_scores[mcode][difficulty] = s: overwrite keeps the original position
  defp put_diff(diffs, difficulty, s) do
    if Enum.any?(diffs, fn {d, _} -> d == difficulty end) do
      Enum.map(diffs, fn
        {d, _old} when d == difficulty -> {difficulty, s}
        other -> other
      end)
    else
      diffs ++ [{difficulty, s}]
    end
  end

  defp best_per_song(pred, game_version) do
    {map, order} =
      "ddr_scores"
      |> search_ordered(pred)
      |> Enum.reduce({%{}, []}, fn {id, record}, {acc, order} ->
        key = {Map.fetch!(record, "mcode"), Map.fetch!(record, "difficulty")}
        score = Map.fetch!(record, "score")

        if !Map.has_key?(acc, key) or score > acc[key]["score"] do
          order = if Map.has_key?(acc, key), do: order, else: order ++ [key]

          {Map.put(acc, key, %{
             "game_version" => game_version,
             "ddr_id" => Map.fetch!(record, "ddr_id"),
             "mcode" => Map.fetch!(record, "mcode"),
             "difficulty" => Map.fetch!(record, "difficulty"),
             "rank" => Map.fetch!(record, "rank"),
             "lamp" => Map.fetch!(record, "lamp"),
             "score" => score,
             "exscore" => Map.fetch!(record, "exscore"),
             "ghostid" => id
           }), order}
        else
          {acc, order}
        end
      end)

    Enum.map(order, &Map.fetch!(map, &1))
  end

  # Names are taken from the version-20 profile first, falling back to the
  # version-19 "common" CSV (KeyError -> UNKNOWN/13, like the Python).
  defp build_names do
    Map.new(DB.all("ddr_profile"), fn p ->
      entry =
        case get_in(p, ["version", "20", "common_dancername"]) do
          nil ->
            name_area_v19(p)

          name ->
            case get_in(p, ["version", "20", "common_area"]) do
              nil -> name_area_v19(p)
              area -> %{"name" => name, "area" => to_int(area)}
            end
        end

      {Map.fetch!(p, "ddr_id"), entry}
    end)
  end

  defp name_area_v19(p) do
    case get_in(p, ["version", "19", "common"]) do
      nil ->
        %{"name" => "UNKNOWN", "area" => 13}

      common ->
        parts = String.split(common, ",")

        %{
          "name" => Enum.fetch!(parts, 27),
          "area" => parts |> Enum.fetch!(3) |> String.trim() |> String.to_integer(16)
        }
    end
  end

  # Python loads webui/ddr.json once at import time; mirrored here by caching
  # the file contents on first use (a later parse_mdb upload only takes
  # effect after a restart, exactly like the Python module global).
  defp mdb_cache do
    State.update(:ddr_playdata3_mdb_cache, :unset, fn
      :unset ->
        cache = load_mdb_from_disk()
        {cache, cache}

      cache ->
        {cache, cache}
    end)
  end

  defp load_mdb_from_disk do
    ddr_metadata = Path.join("webui", "ddr.json")

    if File.exists?(ddr_metadata) do
      mdb = ddr_metadata |> File.read!() |> Jason.decode!()

      music_load =
        mdb
        |> Map.keys()
        |> Enum.sort(:desc)
        |> Enum.flat_map(fn i ->
          mdb
          |> Map.fetch!(i)
          |> Map.fetch!("diffLv")
          |> Enum.with_index()
          |> Enum.flat_map(fn {lvl, idx} ->
            if String.to_integer(lvl) != 0 do
              ["#{i},#{if idx > 4, do: 1, else: 0},#{rem(idx, 5)},0,#{lvl}"]
            else
              []
            end
          end)
        end)

      {mdb, music_load}
    else
      {%{}, []}
    end
  end

  defp find_text(node, tag), do: node |> XNode.child(tag) |> Map.get(:text)

  defp find_int(node, tag), do: node |> find_text(tag) |> String.trim() |> String.to_integer()

  defp text_int(node), do: node |> Map.get(:text) |> String.trim() |> String.to_integer()

  # int(): accepts integers and (whitespace-tolerant) numeric strings
  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_binary(v), do: v |> String.trim() |> String.to_integer()

  # TinyDB doc_id support: the DB GenServer state holds the raw
  # %{"table" => %{"id" => doc}} maps with 1-based, monotonically increasing
  # numeric string ids, exactly like TinyDB's storage.
  defp table_with_ids(table) do
    DB
    |> :sys.get_state()
    |> Map.get(table, %{})
    |> Map.new(fn {id, doc} -> {String.to_integer(id), doc} end)
  end

  defp get_doc_by_id(table, id), do: table |> table_with_ids() |> Map.get(id)

  defp search_ordered(table, %{} = conds) do
    search_ordered(table, fn doc -> Enum.all?(conds, fn {k, v} -> Map.get(doc, k) == v end) end)
  end

  defp search_ordered(table, pred) when is_function(pred, 1) do
    table
    |> table_with_ids()
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.filter(fn {_id, doc} -> pred.(doc) end)
  end
end
