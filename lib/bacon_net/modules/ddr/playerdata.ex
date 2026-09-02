defmodule BaconNet.Modules.Ddr.Playerdata do
  @moduledoc "Port of modules/ddr/playerdata.py (DDR A20, game version 19)."

  alias BaconNet.{Core, DB, E, XNode}

  def routes do
    %{
      prefix: "/local2",
      tag: "local2",
      handlers: [
        {"playerdata", "usergamedata_advanced", :playerdata_usergamedata_advanced},
        {"playerdata", "usergamedata_recv", :playerdata_usergamedata_recv},
        {"playerdata", "usergamedata_send", :playerdata_usergamedata_send}
      ]
    }
  end

  @calories_disp ["Off", "On"]
  @characters [
    "All Character Random",
    "Man Random",
    "Female Random",
    "Yuni",
    "Rage",
    "Afro",
    "Jenny",
    "Emi",
    "Baby-Lon",
    "Gus",
    "Ruby",
    "Alice",
    "Julio",
    "Bonnie",
    "Zero",
    "Rinon"
  ]
  @arrow_skins ["Normal", "X", "Classic", "Cyber", "Medium", "Small", "Dot"]
  @screen_filters ["Off", "Dark", "Darker", "Darkest"]
  @guidelines ["Off", "Border", "Center"]
  @priorities ["Judgment", "Arrow"]
  @timing_disps ["Off", "On"]

  def get_profile(cid), do: DB.get("ddr_profile", %{"card" => cid})

  def get_game_profile(cid, game_version) do
    case get_profile(cid) do
      nil -> nil
      profile -> profile |> Map.fetch!("version") |> Map.get(to_string(game_version))
    end
  end

  def get_common(ddr_id, game_version, idx) do
    profile = DB.get("ddr_profile", %{"ddr_id" => ddr_id})

    if profile != nil do
      profile
      |> Map.fetch!("version")
      |> Map.get(to_string(game_version))
      |> Map.fetch!("common")
      |> String.split(",")
      |> Enum.at(idx)
    else
      0
    end
  end

  def playerdata_usergamedata_advanced(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version
    is_omni = info.rev == "O"

    data = Core.module_node(info) |> XNode.child("data")
    mode = find_text(data, "mode")
    gamesession = find_text(data, "gamesession")
    refid = find_text(data, "refid")

    base = "X0000000000000000000000000000000"

    default =
      String.slice(base, 0, max(String.length(base) - String.length(gamesession), 0)) <>
        gamesession

    all_profiles_for_card = DB.get("ddr_profile", %{"card" => refid})

    response =
      cond do
        mode == "usernew" ->
          shoparea = find_text(data, "shoparea")

          {ddr_id, all_profiles_for_card} =
            if !Map.has_key?(all_profiles_for_card, "ddr_id") do
              ddr_id = :rand.uniform(90_000_000) + 9_999_999
              {ddr_id, Map.put(all_profiles_for_card, "ddr_id", ddr_id)}
            else
              {Map.fetch!(all_profiles_for_card, "ddr_id"), all_profiles_for_card}
            end

          all_profiles_for_card =
            put_in(all_profiles_for_card, ["version", to_string(game_version)], %{
              "game_version" => game_version,
              "calories_disp" => "Off",
              "character" => "All Character Random",
              "arrow_skin" => "Normal",
              "filter" => "Darkest",
              "guideline" => "Center",
              "priority" => "Judgment",
              "timing_disp" => "On",
              "rival_1_ddr_id" => 0,
              "rival_2_ddr_id" => 0,
              "rival_3_ddr_id" => 0,
              "single_grade" => 0,
              "double_grade" => 0
            })

          DB.upsert("ddr_profile", all_profiles_for_card, %{"card" => refid})

          ddr_id_str = Integer.to_string(ddr_id)
          seq = String.slice(ddr_id_str, 0, 4) <> "-" <> String.slice(ddr_id_str, 4..-1//1)

          E.e(
            "response",
            E.e("playerdata", [
              E.e("result", 0, __type: "s32"),
              E.e("seq", seq, __type: "str"),
              E.e("code", ddr_id, __type: "s32"),
              E.e("shoparea", shoparea, __type: "str")
            ])
          )

        mode == "userload" and refid != default ->
          {all_scores, mcode_order, single_grade, double_grade} =
            if all_profiles_for_card != nil do
              ddr_id = Map.fetch!(all_profiles_for_card, "ddr_id")
              profile = get_game_profile(refid, game_version)

              {scores_map, mcode_order} = collect_scores(ddr_id)

              {scores_map, mcode_order, Map.get(profile, "single_grade", 0),
               Map.get(profile, "double_grade", 0)}
            else
              # Python: single_grade/double_grade stay unbound here and the
              # response build dies with NameError at E.grade(...)
              raise "name 'single_grade' is not defined"
            end

          music_nodes =
            for mcode <- mcode_order do
              notes =
                for s <- Map.fetch!(all_scores, mcode) do
                  if Enum.at(s, 0) == 0 do
                    E.e("note")
                  else
                    E.e("note", [
                      E.e("count", Enum.at(s, 0), __type: "u16"),
                      E.e("rank", Enum.at(s, 1), __type: "u8"),
                      E.e("clearkind", Enum.at(s, 2), __type: "u8"),
                      E.e("score", Enum.at(s, 3), __type: "s32"),
                      E.e("ghostid", Enum.at(s, 4), __type: "s32")
                    ])
                  end
                end

              E.e("music", [E.e("mcode", mcode, __type: "u32")] ++ notes)
            end

          event_nodes =
            for event <- 1..99, event not in [4, 6, 7, 8, 14, 47] do
              E.e("eventdata", [
                E.e("eventid", event, __type: "u32"),
                E.e("eventtype", 9999, __type: "s32"),
                E.e("eventno", 0, __type: "u32"),
                E.e("condition", 0, __type: "s64"),
                E.e("reward", 0, __type: "u32"),
                E.e("comptime", 1, __type: "s32"),
                E.e("savedata", 0, __type: "s64")
              ])
            end

          E.e(
            "response",
            E.e(
              "playerdata",
              [
                E.e("result", 0, __type: "s32"),
                E.e("is_new", if(all_profiles_for_card == nil, do: 1, else: 0), __type: "bool"),
                E.e("is_refid_locked", 0, __type: "bool"),
                E.e("eventdata_count_all", 1, __type: "s16")
              ] ++
                music_nodes ++
                event_nodes ++
                [
                  E.e("grade", [
                    E.e("single_grade", single_grade, __type: "u32"),
                    E.e("double_grade", double_grade, __type: "u32")
                  ]),
                  E.e("golden_league", [
                    E.e("league_class", 0, __type: "s32"),
                    E.e("current", [
                      E.e("id", 0, __type: "s32"),
                      E.e("league_name_base64", "", __type: "str"),
                      E.e("start_time", 0, __type: "u64"),
                      E.e("end_time", 0, __type: "u64"),
                      E.e("summary_time", 0, __type: "u64"),
                      E.e("league_status", 0, __type: "s32"),
                      E.e("league_class", 0, __type: "s32"),
                      E.e("league_class_result", 0, __type: "s32"),
                      E.e("ranking_number", 0, __type: "s32"),
                      E.e("total_exscore", 0, __type: "s32"),
                      E.e("total_play_count", 0, __type: "s32"),
                      E.e("join_number", 0, __type: "s32"),
                      E.e("promotion_ranking_number", 0, __type: "s32"),
                      E.e("demotion_ranking_number", 0, __type: "s32"),
                      E.e("promotion_exscore", 0, __type: "s32"),
                      E.e("demotion_exscore", 0, __type: "s32")
                    ])
                  ]),
                  E.e("championship", [
                    E.e("championship_id", 0, __type: "s32"),
                    E.e("name_base64", "", __type: "str"),
                    E.e("lang", [
                      E.e("destinationcodes", "", __type: "str"),
                      E.e("name_base64", "", __type: "str")
                    ]),
                    E.e("music", [
                      E.e("mcode", 0, __type: "u32"),
                      E.e("notetype", 0, __type: "s8"),
                      E.e("playstyle", 0, __type: "s32")
                    ])
                  ]),
                  E.e("preplayable")
                ]
            )
          )

        mode == "ghostload" ->
          ghostid = find_int(data, "ghostid")
          record = get_doc_by_id("ddr_scores", ghostid)

          E.e(
            "response",
            E.e("playerdata", [
              E.e("result", 0, __type: "s32"),
              E.e("ghostdata", [
                E.e("code", Map.fetch!(record, "ddr_id"), __type: "s32"),
                E.e("mcode", Map.fetch!(record, "mcode"), __type: "u32"),
                E.e("notetype", Map.fetch!(record, "difficulty"), __type: "u8"),
                E.e("ghostsize", Map.fetch!(record, "ghostsize"), __type: "s32"),
                E.e("ghost", Map.fetch!(record, "ghost"), __type: "string")
              ])
            ])
          )

        mode == "usersave" and refid != default ->
          timestamp = :os.system_time(:microsecond) / 1_000_000

          ddr_id = find_int(data, "ddrcode")
          playstyle = find_int(data, "playstyle")
          pcbid = find_text(data, "pcbid")
          shoparea = find_text(data, "shoparea")

          note = XNode.children(data, "note")

          if find_int(data, "isgameover") == 0 do
            # Python quirk: the loop body only assigns variables, so the insert
            # below uses the values from the LAST note with stagenum != 0
            # (NameError when no such note exists).
            last =
              Enum.reduce(note, nil, fn n, acc ->
                if find_int(n, "stagenum") != 0, do: extract_note(n), else: acc
              end)

            n = last || raise("name 'mcode' is not defined")

            DB.insert("ddr_scores", %{
              "timestamp" => timestamp,
              "pcbid" => pcbid,
              "shoparea" => shoparea,
              "game_version" => game_version,
              "ddr_id" => ddr_id,
              "playstyle" => playstyle,
              "mcode" => n.mcode,
              "difficulty" => n.difficulty,
              "rank" => n.rank,
              "lamp" => n.lamp,
              "score" => n.score,
              "exscore" => n.exscore,
              "maxcombo" => n.maxcombo,
              "life" => n.life,
              "fastcount" => n.fastcount,
              "slowcount" => n.slowcount,
              "judge_marvelous" => n.judge_marvelous,
              "judge_perfect" => n.judge_perfect,
              "judge_great" => n.judge_great,
              "judge_good" => n.judge_good,
              "judge_boo" => n.judge_boo,
              "judge_miss" => n.judge_miss,
              "judge_ok" => n.judge_ok,
              "judge_ng" => n.judge_ng,
              "calorie" => n.calorie,
              "ghostsize" => n.ghostsize,
              "ghost" => n.ghost,
              "opt_speed" => n.opt_speed,
              "opt_boost" => n.opt_boost,
              "opt_appearance" => n.opt_appearance,
              "opt_turn" => n.opt_turn,
              "opt_dark" => n.opt_dark,
              "opt_scroll" => n.opt_scroll,
              "opt_arrowcolor" => n.opt_arrowcolor,
              "opt_cut" => n.opt_cut,
              "opt_freeze" => n.opt_freeze,
              "opt_jump" => n.opt_jump,
              "opt_arrowshape" => n.opt_arrowshape,
              "opt_filter" => n.opt_filter,
              "opt_guideline" => n.opt_guideline,
              "opt_gauge" => n.opt_gauge,
              "opt_judgepriority" => n.opt_judgepriority,
              "opt_timing" => n.opt_timing
            })

            save_best(game_version, ddr_id, playstyle, n.mcode, n.difficulty, %{
              rank: n.rank,
              lamp: n.lamp,
              score: n.score,
              exscore: n.exscore
            })
          else
            single_grade =
              data |> XNode.child("grade") |> XNode.child("single_grade") |> text_int()

            double_grade =
              data |> XNode.child("grade") |> XNode.child("double_grade") |> text_int()

            profile = get_profile(refid)
            version = Map.fetch!(profile, "version")
            game_profile = Map.get(version, to_string(game_version), %{})

            # workaround to save the correct dan grade by using the course mcode
            # because omnimix force unlocks all dan courses with <grade __type="u8">1</grade> in coursedb.xml
            {single_grade, double_grade} =
              if is_omni do
                n = List.first(note)
                mcode = find_int(n, "mcode")

                if find_int(n, "clearkind") != 1 do
                  Enum.reduce(
                    Enum.with_index(1000..1010, 1),
                    {single_grade, double_grade},
                    fn {course_id, grade}, {sg, dg} ->
                      cond do
                        playstyle in [0, 2] and mcode in [course_id, course_id + 11] ->
                          {grade, dg}

                        playstyle == 1 and mcode in [course_id + 1000, course_id + 1000 + 11] ->
                          {sg, grade}

                        true ->
                          {sg, dg}
                      end
                    end
                  )
                else
                  {single_grade, double_grade}
                end
              else
                {single_grade, double_grade}
              end

            game_profile =
              game_profile
              |> Map.put(
                "single_grade",
                max(single_grade, Map.get(game_profile, "single_grade", single_grade))
              )
              |> Map.put(
                "double_grade",
                max(double_grade, Map.get(game_profile, "double_grade", double_grade))
              )

            profile =
              Map.put(profile, "version", Map.put(version, to_string(game_version), game_profile))

            DB.upsert("ddr_profile", profile, %{"card" => refid})
          end

          E.e("response", E.e("playerdata", E.e("result", 0, __type: "s32")))

        mode == "rivalload" ->
          loadflag = find_int(data, "loadflag")
          ddrcode = find_int(data, "ddrcode")
          pcbid = find_text(data, "pcbid")
          shoparea = find_text(data, "shoparea")

          scores =
            case loadflag do
              1 ->
                best_per_song(
                  fn doc -> Map.get(doc, "pcbid") == pcbid and Map.get(doc, "ddr_id") != 0 end,
                  game_version
                )

              2 ->
                best_per_song(
                  fn doc ->
                    Map.get(doc, "shoparea") == shoparea and Map.get(doc, "ddr_id") != 0
                  end,
                  game_version
                )

              4 ->
                best_per_song(fn doc -> Map.get(doc, "ddr_id") != 0 end, game_version)

              flag when flag in [8, 16, 32] ->
                "ddr_scores_best"
                |> search_ordered(%{"ddr_id" => ddrcode})
                |> Enum.map(fn {_id, doc} -> doc end)

              # Python: scores stays unbound, NameError at `for r in scores`
              _ ->
                raise "name 'scores' is not defined"
            end

          names = build_names(game_version)

          record_nodes =
            for r <- scores do
              {name, area} =
                case Map.get(names, Map.fetch!(r, "ddr_id")) do
                  nil -> {"UNKNOWN", 13}
                  entry -> {Map.fetch!(entry, "name"), Map.fetch!(entry, "area")}
                end

              E.e("record", [
                E.e("mcode", Map.fetch!(r, "mcode"), __type: "u32"),
                E.e("notetype", Map.fetch!(r, "difficulty"), __type: "u8"),
                E.e("rank", Map.fetch!(r, "rank"), __type: "u8"),
                E.e("clearkind", Map.fetch!(r, "lamp"), __type: "u8"),
                E.e("flagdata", 0, __type: "u8"),
                E.e("name", name, __type: "str"),
                E.e("area", area, __type: "s32"),
                E.e("code", Map.fetch!(r, "ddr_id"), __type: "s32"),
                E.e("score", Map.fetch!(r, "score"), __type: "s32"),
                E.e("ghostid", Map.fetch!(r, "ghostid"), __type: "s32")
              ])
            end

          E.e(
            "response",
            E.e("playerdata", [
              E.e("result", 0, __type: "s32"),
              E.e("data", [E.e("recordtype", loadflag, __type: "s32")] ++ record_nodes)
            ])
          )

        mode == "inheritance" ->
          E.e(
            "response",
            E.e("playerdata", [
              E.e("result", 0, __type: "s32"),
              E.e("InheritanceStatus", 1, __type: "s32")
            ])
          )

        true ->
          E.e("response", E.e("playerdata", E.e("result", 1, __type: "s32")))
      end

    Core.send_response(conn, info, response)
  end

  def playerdata_usergamedata_recv(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    module_node = Core.module_node(info)
    data = module_node && XNode.child(module_node, "data")
    cid = data && find_text(data, "refid")
    profile = cid && get_game_profile(cid, game_version)

    if profile == nil do
      Core.send_response(
        conn,
        info,
        E.e("response", E.e("playerdata", E.e("result", 1, __type: "s32")))
      )
    else
      common = profile |> Map.fetch!("common") |> String.split(",")

      common =
        List.replace_at(
          common,
          5,
          index_of!(@calories_disp, Map.fetch!(profile, "calories_disp"))
        )

      common =
        List.replace_at(
          common,
          6,
          @characters
          |> index_of!(Map.fetch!(profile, "character"))
          |> Integer.to_string(16)
          |> String.downcase()
        )

      common = List.replace_at(common, 9, 1)
      common_load = Enum.map_join(common, ",", &to_string/1)

      option = profile |> Map.fetch!("option") |> String.split(",")

      option =
        List.replace_at(option, 13, index_of!(@arrow_skins, Map.fetch!(profile, "arrow_skin")))

      option =
        List.replace_at(option, 14, index_of!(@screen_filters, Map.fetch!(profile, "filter")))

      option =
        List.replace_at(option, 15, index_of!(@guidelines, Map.fetch!(profile, "guideline")))

      option =
        List.replace_at(option, 17, index_of!(@priorities, Map.fetch!(profile, "priority")))

      option =
        List.replace_at(option, 18, index_of!(@timing_disps, Map.fetch!(profile, "timing_disp")))

      option_load = Enum.map_join(option, ",", &to_string/1)

      rival = profile |> Map.fetch!("rival") |> String.split(",")

      rival_ids = [
        Map.get(profile, "rival_1_ddr_id", 0),
        Map.get(profile, "rival_2_ddr_id", 0),
        Map.get(profile, "rival_3_ddr_id", 0)
      ]

      rival =
        rival_ids
        |> Enum.with_index(3)
        |> Enum.reduce(rival, fn {r, idx}, acc ->
          if r != 0 do
            acc
            |> List.replace_at(idx, idx - 2)
            |> List.replace_at(idx + 8, get_common(r, game_version, 4))
          else
            acc
          end
        end)

      rival_load = Enum.map_join(rival, ",", &to_string/1)

      load = [
        common_load |> String.split("ffffffff,COMMON,") |> Enum.fetch!(1) |> Base.encode64(),
        option_load |> String.split("ffffffff,OPTION,") |> Enum.fetch!(1) |> Base.encode64(),
        profile
        |> Map.fetch!("last")
        |> String.split("ffffffff,LAST,")
        |> Enum.fetch!(1)
        |> Base.encode64(),
        rival_load |> String.split("ffffffff,RIVAL,") |> Enum.fetch!(1) |> Base.encode64()
      ]

      response =
        E.e(
          "response",
          E.e("playerdata", [
            E.e("result", 0, __type: "s32"),
            E.e("player", [
              E.e("record", for(p <- load, do: E.e("d", p, __type: "str"))),
              E.e("record_num", 4, __type: "u32")
            ])
          ])
        )

      Core.send_response(conn, info, response)
    end
  end

  def playerdata_usergamedata_send(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    data = Core.module_node(info) |> XNode.child("data")
    cid = find_text(data, "refid")
    num = find_int(data, "datanum")

    profile = get_profile(cid)
    version = Map.fetch!(profile, "version")
    game_profile = Map.get(version, to_string(game_version), %{})

    record = XNode.child(data, "record")

    decode = fn i ->
      record.children
      |> Enum.fetch!(i)
      |> Map.get(:text)
      |> String.split("<bin1")
      |> hd()
      |> b64decode()
      |> utf8_ignore()
    end

    game_profile =
      case num do
        1 ->
          Map.put(game_profile, "common", decode.(0))

        4 ->
          game_profile =
            game_profile
            |> Map.put("common", decode.(0))
            |> Map.put("option", decode.(1))
            |> Map.put("last", decode.(2))
            |> Map.put("rival", decode.(3))

          Enum.reduce(["rival_1_ddr_id", "rival_2_ddr_id", "rival_3_ddr_id"], game_profile, fn r,
                                                                                               acc ->
            Map.put_new(acc, r, 0)
          end)

        _ ->
          game_profile
      end

    profile = Map.put(profile, "version", Map.put(version, to_string(game_version), game_profile))

    DB.upsert("ddr_profile", profile, %{"card" => cid})

    response = E.e("response", E.e("playerdata", E.e("result", 0, __type: "s32")))

    Core.send_response(conn, info, response)
  end

  ## Helpers

  # mcode -> 9-entry list of [count, rank, clearkind, score, ghostid]
  # (not 10, there is no dp beginner), preserving insertion order
  defp collect_scores(ddr_id) do
    "ddr_scores_best"
    |> search_ordered(%{"ddr_id" => ddr_id})
    |> Enum.reduce({%{}, []}, fn {_id, record}, {acc, order} ->
      mcode = Map.fetch!(record, "mcode")
      difficulty = Map.fetch!(record, "difficulty")

      entry = Map.get(acc, mcode, List.duplicate([0, 0, 0, 0, 0], 9))

      entry =
        List.replace_at(entry, difficulty, [
          1,
          Map.fetch!(record, "rank"),
          Map.fetch!(record, "lamp"),
          Map.fetch!(record, "score"),
          Map.fetch!(record, "ghostid")
        ])

      order = if Map.has_key?(acc, mcode), do: order, else: order ++ [mcode]
      {Map.put(acc, mcode, entry), order}
    end)
  end

  defp extract_note(n) do
    %{
      mcode: find_int(n, "mcode"),
      difficulty: find_int(n, "notetype"),
      rank: find_int(n, "rank"),
      lamp: find_int(n, "clearkind"),
      score: find_int(n, "score"),
      exscore: find_int(n, "exscore"),
      maxcombo: find_int(n, "maxcombo"),
      life: find_int(n, "life"),
      fastcount: find_int(n, "fastcount"),
      slowcount: find_int(n, "slowcount"),
      judge_marvelous: find_int(n, "judge_marvelous"),
      judge_perfect: find_int(n, "judge_perfect"),
      judge_great: find_int(n, "judge_great"),
      judge_good: find_int(n, "judge_good"),
      judge_boo: find_int(n, "judge_boo"),
      judge_miss: find_int(n, "judge_miss"),
      judge_ok: find_int(n, "judge_ok"),
      judge_ng: find_int(n, "judge_ng"),
      calorie: find_int(n, "calorie"),
      ghostsize: find_int(n, "ghostsize"),
      ghost: find_text(n, "ghost"),
      opt_speed: find_int(n, "opt_speed"),
      opt_boost: find_int(n, "opt_boost"),
      opt_appearance: find_int(n, "opt_appearance"),
      opt_turn: find_int(n, "opt_turn"),
      opt_dark: find_int(n, "opt_dark"),
      opt_scroll: find_int(n, "opt_scroll"),
      opt_arrowcolor: find_int(n, "opt_arrowcolor"),
      opt_cut: find_int(n, "opt_cut"),
      opt_freeze: find_int(n, "opt_freeze"),
      opt_jump: find_int(n, "opt_jump"),
      opt_arrowshape: find_int(n, "opt_arrowshape"),
      opt_filter: find_int(n, "opt_filter"),
      opt_guideline: find_int(n, "opt_guideline"),
      opt_gauge: find_int(n, "opt_gauge"),
      opt_judgepriority: find_int(n, "opt_judgepriority"),
      opt_timing: find_int(n, "opt_timing")
    }
  end

  defp save_best(game_version, ddr_id, playstyle, mcode, difficulty, new) do
    conds = %{"ddr_id" => ddr_id, "mcode" => mcode, "difficulty" => difficulty}
    best = DB.get("ddr_scores_best", conds) || %{}

    best_score_data = %{
      "game_version" => game_version,
      "ddr_id" => ddr_id,
      "playstyle" => playstyle,
      "mcode" => mcode,
      "difficulty" => difficulty,
      "rank" => min(new.rank, Map.get(best, "rank", new.rank)),
      "lamp" => max(new.lamp, Map.get(best, "lamp", new.lamp)),
      "score" => max(new.score, Map.get(best, "score", new.score)),
      "exscore" => max(new.exscore, Map.get(best, "exscore", new.exscore))
    }

    ghostid =
      "ddr_scores"
      |> search_ordered(fn doc ->
        Map.get(doc, "ddr_id") == ddr_id and Map.get(doc, "mcode") == mcode and
          Map.get(doc, "difficulty") == difficulty and
          Map.get(doc, "score") == max(new.score, Map.get(best, "score", new.score))
      end)
      |> List.first()

    best_score_data =
      case ghostid do
        {id, _doc} -> Map.put(best_score_data, "ghostid", id)
        nil -> Map.put(best_score_data, "ghostid", -1)
      end

    DB.upsert("ddr_scores_best", best_score_data, conds)
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

  defp build_names(game_version) do
    Map.new(DB.all("ddr_profile"), fn p ->
      entry =
        case get_in(p, ["version", to_string(game_version), "common"]) do
          nil ->
            %{"name" => "UNKNOWN", "area" => 13}

          common ->
            parts = String.split(common, ",")

            %{
              "name" => Enum.fetch!(parts, 27),
              "area" => parts |> Enum.fetch!(3) |> String.trim() |> String.to_integer(16)
            }
        end

      {Map.fetch!(p, "ddr_id"), entry}
    end)
  end

  defp find_text(node, tag), do: node |> XNode.child(tag) |> Map.get(:text)

  defp find_int(node, tag), do: node |> find_text(tag) |> String.trim() |> String.to_integer()

  defp text_int(node), do: node |> Map.get(:text) |> String.trim() |> String.to_integer()

  # list.index(): raises when the value is missing (Python ValueError)
  defp index_of!(list, value) do
    case Enum.find_index(list, &(&1 == value)) do
      nil -> raise "ValueError: #{inspect(value)} is not in list"
      idx -> idx
    end
  end

  # Python base64.b64decode(validate=False): non-alphabet characters are
  # discarded before decoding.
  defp b64decode(s) do
    s
    |> :binary.bin_to_list()
    |> Enum.filter(&(&1 in ~c"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="))
    |> IO.iodata_to_binary()
    |> Base.decode64!()
  end

  # Python bytes.decode("utf-8", errors="ignore")
  defp utf8_ignore(<<>>), do: <<>>

  defp utf8_ignore(bin) do
    case :unicode.characters_to_binary(bin, :utf8, :utf8) do
      {:error, good, <<_bad, rest::binary>>} -> good <> utf8_ignore(rest)
      {:incomplete, good, _rest} -> good
      res when is_binary(res) -> res
    end
  end

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
