defmodule BaconNet.Modules.Gitadora.Gametop do
  @moduledoc "Port of modules/gitadora/gametop.py."

  import Bitwise

  alias BaconNet.{Core, DB, E, XNode}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"{ver}_gametop", "get", :gitadora_gametop_get}
      ]
    }
  end

  defp get_profile(cid) do
    DB.get("gitadora_profile", %{"card" => cid})
  end

  defp get_game_profile(cid, game_version) do
    profile = get_profile(cid)

    get_in(profile, ["version", to_string(game_version)])
  end

  def gitadora_gametop_get(conn, ver) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version
    spec = info.spec

    g =
      cond do
        spec in ["A", "C"] -> "guitarfreaks"
        spec in ["B", "D"] -> "drummania"
      end

    data = Core.module_node(info) |> XNode.child("player")
    no = XNode.attr_int(data, "no")
    dataid = data |> XNode.child("refid") |> Map.get(:text)
    profile = get_game_profile(dataid, game_version)
    gitadora_id = get_profile(dataid)["gitadora_id"]

    records =
      "#{g}_scores_best"
      |> DB.search(%{"gitadora_id" => gitadora_id})
      |> Enum.reduce(%{}, fn record, records ->
        s = %{
          "musicid" => record["musicid"],
          "seq" => record["seq"],
          "skill" => record["skill"],
          "clear" => record["clear"],
          "fullcombo" => record["fullcombo"],
          "excellent" => record["excellent"],
          "perc" => record["perc"],
          "rank" => record["rank"],
          "meter" => record["meter"],
          "meter_prog" => record["meter_prog"],
          "sdata" => 0
        }

        entry =
          Map.get(records, record["musicid"], %{
            "order" => map_size(records),
            "seq" => %{}
          })

        Map.put(records, record["musicid"], %{
          entry
          | "seq" => Map.put(entry["seq"], record["seq"], s)
        })
      end)

    mlist =
      records
      |> Enum.sort_by(fn {_musicid, entry} -> entry["order"] end)
      |> Enum.map(fn {musicid, entry} ->
        data = %{
          "musicid" => musicid,
          "mdata" => List.duplicate(-1, 20),
          "flag" => List.duplicate(0, 5),
          "sdata" => List.duplicate(-1, 2),
          "meter" => List.duplicate(0, 8),
          "meter_prog" => List.duplicate(-1, 8)
        }

        Enum.reduce(entry["seq"], data, fn {seq, s}, data ->
          seqidx = if is_integer(seq), do: seq, else: String.to_integer(seq)

          mdata =
            data["mdata"]
            |> List.replace_at(seqidx, s["perc"])
            |> List.replace_at(8 + seqidx, if(s["clear"] != 0, do: s["rank"], else: -1))

          flag = data["flag"]

          flag =
            if s["fullcombo"] != 0 do
              List.replace_at(flag, 0, Enum.at(flag, 0) ||| 1 <<< seqidx)
            else
              flag
            end

          flag =
            if s["excellent"] != 0 do
              List.replace_at(flag, 1, Enum.at(flag, 1) ||| 1 <<< seqidx)
            else
              flag
            end

          # Clear flag/count score towards profile stats
          flag = List.replace_at(flag, 2, Enum.at(flag, 2) ||| s["clear"] <<< seqidx)

          meter = List.replace_at(data["meter"], seqidx - 1, s["meter"])
          meter_prog = List.replace_at(data["meter_prog"], seqidx - 1, s["meter_prog"])

          %{data | "mdata" => mdata, "flag" => flag, "meter" => meter, "meter_prog" => meter_prog}
        end)
      end)

    mlist =
      if mlist == [] do
        [
          %{
            "musicid" => -1,
            "mdata" => List.duplicate(-1, 20),
            "flag" => List.duplicate(0, 5),
            "sdata" => List.duplicate(-1, 2),
            "meter" => List.duplicate(0, 8),
            "meter_prog" => List.duplicate(-1, 8)
          }
        ]
      else
        mlist
      end

    pg = profile[g]

    rivals = Map.get(profile, "rival_card_ids", [])

    response =
      E.e(
        "response",
        E.e(
          "#{ver}_gametop",
          E.e(
            "player",
            [
              E.e("now_date", round(:os.system_time(:millisecond) / 1000), __type: "u64"),
              E.e(
                "musiclist",
                Enum.map(mlist, fn m ->
                  E.e(
                    "musicdata",
                    [
                      E.e("mdata", m["mdata"], __type: "s16"),
                      E.e("flag", m["flag"], __type: "u16"),
                      E.e("sdata", m["sdata"], __type: "s16"),
                      E.e("meter", m["meter"], __type: "u64"),
                      E.e("meter_prog", m["meter_prog"], __type: "s16")
                    ],
                    musicid: m["musicid"]
                  )
                end),
                nr: length(mlist)
              ),
              E.e(
                "secretmusic",
                E.e("music", [
                  E.e("musicid", 1, __type: "s32"),
                  E.e("seq", 1, __type: "u16"),
                  E.e("kind", 1, __type: "s32")
                ])
              ),
              E.e(
                "chara_list",
                E.e(
                  "chara",
                  E.e("charaid", 1, __type: "s32")
                )
              ),
              E.e(
                "title_parts",
                E.e("parts", "", __type: "str")
              ),
              E.e(
                "information",
                E.e("info", pg["information"], __type: "u32")
              ),
              E.e(
                "reward",
                E.e("status", pg["reward"], __type: "u32")
              ),
              rivaldata(rivals),
              E.e("frienddata", E.e("friend")),
              E.e("thanks_medal", [
                E.e("medal", pg["thanks_medal_medal"], __type: "s32"),
                E.e("grant_medal", 0, __type: "s32"),
                E.e("grant_total_medal", pg["thanks_medal_granted_total_medal"], __type: "s32")
              ]),
              E.e(
                "skindata",
                E.e("skin", List.duplicate(0xFFFFFFFF, 100), __type: "u32")
              ),
              E.e("battledata", [
                E.e("info", [
                  E.e("orb", 0, __type: "s32"),
                  E.e("get_gb_point", 0, __type: "s32"),
                  E.e("send_gb_point", 0, __type: "s32")
                ]),
                E.e("greeting", [
                  E.e("greeting_1", "hi", __type: "str"),
                  E.e("greeting_2", "hi", __type: "str"),
                  E.e("greeting_3", "hi", __type: "str"),
                  E.e("greeting_4", "hi", __type: "str"),
                  E.e("greeting_5", "hi", __type: "str"),
                  E.e("greeting_6", "hi", __type: "str"),
                  E.e("greeting_7", "hi", __type: "str"),
                  E.e("greeting_8", "hi", __type: "str"),
                  E.e("greeting_9", "hi", __type: "str")
                ]),
                E.e("setting", [
                  E.e("matching", 1, __type: "s32"),
                  E.e("info_level", 1, __type: "s32")
                ]),
                E.e("score", [
                  E.e("battle_class", 100, __type: "s32"),
                  E.e("max_battle_class", 100, __type: "s32"),
                  E.e("battle_point", 100, __type: "s32"),
                  E.e("win", 100, __type: "s32"),
                  E.e("lose", 100, __type: "s32"),
                  E.e("draw", 100, __type: "s32"),
                  E.e("consecutive_win", 100, __type: "s32"),
                  E.e("max_consecutive_win", 100, __type: "s32"),
                  E.e("glorious_win", 100, __type: "s32"),
                  E.e("max_defeat_skill", 100, __type: "s32"),
                  E.e("latest_result", 5, __type: "s32")
                ]),
                E.e("history")
              ]),
              E.e("is_free_ok", 0, __type: "bool"),
              E.e("ranking", [
                E.e("skill", [
                  E.e("rank", 1, __type: "s32"),
                  E.e("total_nr", 1, __type: "s32")
                ]),
                E.e("all_skill", [
                  E.e("rank", 1, __type: "s32"),
                  E.e("total_nr", 1, __type: "s32")
                ])
              ]),
              E.e("stage_result"),
              E.e("monthly_skill"),
              E.e("event_skill", [
                E.e("skill", 1, __type: "s32"),
                E.e("ranking", [
                  E.e("rank", 1, __type: "s32"),
                  E.e("total_nr", 1, __type: "s32")
                ]),
                E.e("eventlist")
              ]),
              E.e("event_score", E.e("event_list")),
              E.e("rockwave", E.e("score_list")),
              E.e("deluxe", [
                E.e("deluxe_content", 0, __type: "s32"),
                E.e("target_id", 0, __type: "s32"),
                E.e("multiply", 0, __type: "s32"),
                E.e("point", 0, __type: "s32")
              ]),
              E.e("galaxy_parade", [
                E.e("score_list"),
                E.e("last_corner_id", 0, __type: "s32"),
                E.e("chara_list"),
                E.e("last_sort_category", 0, __type: "s32"),
                E.e("last_sort_order", 0, __type: "s32"),
                E.e("team_member", [
                  E.e("chara_id_guitar", 0, __type: "s32"),
                  E.e("chara_id_bass", 0, __type: "s32"),
                  E.e("chara_id_drum", 0, __type: "s32"),
                  E.e("chara_id_free1", 0, __type: "s32"),
                  E.e("chara_id_free2", 0, __type: "s32")
                ])
              ]),
              E.e("livehouse", E.e("score_list", E.e("last_livehouse", 0, __type: "s32"))),
              E.e("jubeat_omiyage_challenge"),
              E.e("light_mode_reward_item", [
                E.e("itemid", -1, __type: "s32"),
                E.e("rarity", 0, __type: "s32")
              ]),
              E.e("standard_mode_reward_item", [
                E.e("itemid", -1, __type: "s32"),
                E.e("rarity", 0, __type: "s32")
              ]),
              E.e("delux_mode_reward_item", [
                E.e("itemid", -1, __type: "s32"),
                E.e("rarity", 0, __type: "s32")
              ]),
              E.e("kac2018", [
                E.e("entry_status", 0, __type: "s32"),
                E.e("data", [
                  E.e("term", 0, __type: "s32"),
                  E.e("total_score", 0, __type: "s32"),
                  E.e("score", List.duplicate(0, 6), __type: "s32"),
                  E.e("music_type", List.duplicate(0, 6), __type: "s32"),
                  E.e("play_count", List.duplicate(0, 6), __type: "s32")
                ])
              ]),
              E.e("sticker_campaign"),
              E.e(
                "kac2017",
                E.e("entry_status", 0, __type: "s32")
              ),
              E.e("nostalgia_concert"),
              E.e("bemani_summer_2018", [
                E.e("linkage_id", -1, __type: "s32"),
                E.e("is_entry", 0, __type: "bool"),
                E.e("target_music_idx", -1, __type: "s32"),
                E.e("point_1", 0, __type: "s32"),
                E.e("point_2", 0, __type: "s32"),
                E.e("point_3", 0, __type: "s32"),
                E.e("point_4", 0, __type: "s32"),
                E.e("point_5", 0, __type: "s32"),
                E.e("point_6", 0, __type: "s32"),
                E.e("point_7", 0, __type: "s32"),
                E.e("reward_1", 0, __type: "bool"),
                E.e("reward_2", 0, __type: "bool"),
                E.e("reward_3", 0, __type: "bool"),
                E.e("reward_4", 0, __type: "bool"),
                E.e("reward_5", 0, __type: "bool"),
                E.e("reward_6", 0, __type: "bool"),
                E.e("reward_7", 0, __type: "bool"),
                E.e("unlock_status_1", 0, __type: "s32"),
                E.e("unlock_status_2", 0, __type: "s32"),
                E.e("unlock_status_3", 0, __type: "s32"),
                E.e("unlock_status_4", 0, __type: "s32"),
                E.e("unlock_status_5", 0, __type: "s32"),
                E.e("unlock_status_6", 0, __type: "s32"),
                E.e("unlock_status_7", 0, __type: "s32")
              ]),
              E.e("thanksgiving", [
                E.e("term", 0, __type: "u8"),
                E.e("score", [
                  E.e("one_day_play_cnt", 0, __type: "s32"),
                  E.e("one_day_lottery_cnt", 0, __type: "s32"),
                  E.e("lucky_star", 0, __type: "s32"),
                  E.e("bear_mark", 0, __type: "s32"),
                  E.e("play_date_ms", 0, __type: "u64")
                ]),
                E.e(
                  "lottery_result",
                  E.e("unlock_bit", 0, __type: "u64")
                )
              ]),
              E.e("lotterybox"),
              E.e(
                "long_otobear_fes_1",
                E.e("point", 0, __type: "s32")
              ),
              E.e(
                "phrase_combo_challenge",
                E.e("point", 0, __type: "s32")
              )
            ] ++
              Enum.map(2..20, fn x ->
                E.e("phrase_combo_challenge_#{x}", E.e("point", 0, __type: "s32"))
              end) ++
              [
                E.e(
                  "bear_fes",
                  Enum.map(1..4, fn x ->
                    E.e("bear_fes_#{x}", [
                      E.e("stage", 0, __type: "s32"),
                      E.e("point", List.duplicate(0, 8), __type: "s32")
                    ])
                  end)
                ),
                E.e(
                  "monstar_subjugation",
                  Enum.map(1..3, fn x ->
                    E.e("monstar_subjugation_#{x}", [
                      E.e("stage", 0, __type: "s32"),
                      E.e("point_1", 0, __type: "s32"),
                      E.e("point_2", 0, __type: "s32"),
                      E.e("point_3", 0, __type: "s32")
                    ])
                  end)
                )
              ] ++
              Enum.map(1..3, fn x ->
                E.e("kouyou_challenge_#{x}", E.e("point", 0, __type: "s32"))
              end) ++
              [
                E.e(
                  "sdvx_stamprally3",
                  E.e("point", 0, __type: "s32")
                ),
                E.e(
                  "chronicle_1",
                  E.e("point", 0, __type: "s32")
                ),
                E.e("playerboard", [
                  E.e("index", 1, __type: "s32"),
                  E.e("is_active", 1, __type: "bool"),
                  E.e("sticker", [
                    E.e("id", 479, __type: "s32"),
                    E.e("pos_x", 160, __type: "float"),
                    E.e("pos_y", 235, __type: "float"),
                    E.e("scale_x", 1, __type: "float"),
                    E.e("scale_y", 1, __type: "float"),
                    E.e("rotate", 0, __type: "float")
                  ]),
                  E.e("sticker", [
                    E.e("id", 172, __type: "s32"),
                    E.e("pos_x", 160, __type: "float"),
                    E.e("pos_y", 235, __type: "float"),
                    E.e("scale_x", 1, __type: "float"),
                    E.e("scale_y", 1, __type: "float"),
                    E.e("rotate", 0, __type: "float")
                  ]),
                  E.e("sticker", [
                    E.e("id", 379, __type: "s32"),
                    E.e("pos_x", 175, __type: "float"),
                    E.e("pos_y", 175, __type: "float"),
                    E.e("scale_x", 0.4, __type: "float"),
                    E.e("scale_y", 0.4, __type: "float"),
                    E.e("rotate", 5, __type: "float")
                  ]),
                  E.e("sticker", [
                    E.e("id", 172, __type: "s32"),
                    E.e("pos_x", 175, __type: "float"),
                    E.e("pos_y", 265, __type: "float"),
                    E.e("scale_x", 1, __type: "float"),
                    E.e("scale_y", 1, __type: "float"),
                    E.e("rotate", 0, __type: "float")
                  ]),
                  E.e("sticker", [
                    E.e("id", 179, __type: "s32"),
                    E.e("pos_x", 69, __type: "float"),
                    E.e("pos_y", 420, __type: "float"),
                    E.e("scale_x", 1, __type: "float"),
                    E.e("scale_y", 1, __type: "float"),
                    E.e("rotate", 0, __type: "float")
                  ])
                ]),
                E.e("player_info", [
                  E.e("player_type", 1, __type: "s8"),
                  E.e("did", 1, __type: "s32"),
                  E.e("name", profile["name"], __type: "str"),
                  E.e("title", profile["title"], __type: "str"),
                  E.e("charaid", profile["charaid"], __type: "s32")
                ]),
                E.e("customdata", [
                  E.e("playstyle", pg["customdata_playstyle"], __type: "s32"),
                  E.e("custom", pg["customdata_custom"], __type: "s32")
                ]),
                E.e("playinfo", [
                  E.e("cabid", pg["playinfo_cabid"], __type: "s32"),
                  E.e("play", pg["playinfo_play"], __type: "s32"),
                  E.e("playtime", pg["playinfo_playtime"], __type: "s32"),
                  E.e("playterm", pg["playinfo_playterm"], __type: "s32"),
                  E.e("session_cnt", pg["playinfo_session_cnt"], __type: "s32"),
                  E.e("matching_num", pg["playinfo_matching_num"], __type: "s32"),
                  E.e("extra_stage", pg["playinfo_extra_stage"], __type: "s32"),
                  E.e("extra_play", pg["playinfo_extra_play"], __type: "s32"),
                  E.e("extra_clear", pg["playinfo_extra_clear"], __type: "s32"),
                  E.e("encore_play", pg["playinfo_encore_play"], __type: "s32"),
                  E.e("encore_clear", pg["playinfo_encore_clear"], __type: "s32"),
                  E.e("pencore_play", pg["playinfo_pencore_play"], __type: "s32"),
                  E.e("pencore_clear", pg["playinfo_pencore_clear"], __type: "s32"),
                  E.e("max_clear_diff", pg["playinfo_max_clear_diff"], __type: "s32"),
                  E.e("max_full_diff", pg["playinfo_max_full_diff"], __type: "s32"),
                  E.e("max_exce_diff", pg["playinfo_max_exce_diff"], __type: "s32"),
                  E.e("clear_num", pg["playinfo_clear_num"], __type: "s32"),
                  E.e("full_num", pg["playinfo_full_num"], __type: "s32"),
                  E.e("exce_num", pg["playinfo_exce_num"], __type: "s32"),
                  E.e("no_num", pg["playinfo_no_num"], __type: "s32"),
                  E.e("e_num", pg["playinfo_e_num"], __type: "s32"),
                  E.e("d_num", pg["playinfo_d_num"], __type: "s32"),
                  E.e("c_num", pg["playinfo_c_num"], __type: "s32"),
                  E.e("b_num", pg["playinfo_b_num"], __type: "s32"),
                  E.e("a_num", pg["playinfo_a_num"], __type: "s32"),
                  E.e("s_num", pg["playinfo_s_num"], __type: "s32"),
                  E.e("ss_num", pg["playinfo_ss_num"], __type: "s32"),
                  E.e("last_category", pg["playinfo_last_category"], __type: "s32"),
                  E.e("last_musicid", pg["playinfo_last_musicid"], __type: "s32"),
                  E.e("last_seq", pg["playinfo_last_seq"], __type: "s32"),
                  E.e("disp_level", pg["playinfo_disp_level"], __type: "s32")
                ]),
                E.e("tutorial", [
                  E.e("progress", pg["tutorial_progress"], __type: "s32"),
                  E.e("disp_state", pg["tutorial_disp_state"], __type: "u32")
                ]),
                E.e("skilldata", [
                  E.e("skill", pg["skilldata_skill"], __type: "s32"),
                  E.e("all_skill", pg["skilldata_allskill"], __type: "s32"),
                  E.e("old_skill", pg["skilldata_skill"], __type: "s32"),
                  E.e("old_all_skill", pg["skilldata_allskill"], __type: "s32")
                ]),
                E.e("favoritemusic", [
                  E.e("list_1", pg["favorite_music_list_1"], __type: "s32"),
                  E.e("list_2", pg["favorite_music_list_2"], __type: "s32"),
                  E.e("list_3", pg["favorite_music_list_3"], __type: "s32")
                ]),
                E.e("recommend_musicid_list", pg["recommend_musicid_list"], __type: "s32"),
                E.e(
                  "record",
                  Enum.map(["guitarfreaks", "drummania"], fn rg ->
                    E.e(if(rg == "guitarfreaks", do: "gf", else: "dm"), [
                      E.e("max_record", [
                        E.e("skill", profile[rg]["record_max_skill"], __type: "s32"),
                        E.e("all_skill", profile[rg]["record_max_all_skill"], __type: "s32"),
                        E.e("clear_diff", profile[rg]["record_max_clear_diff"], __type: "s32"),
                        E.e("full_diff", profile[rg]["record_max_full_diff"], __type: "s32"),
                        E.e("exce_diff", profile[rg]["record_max_exce_diff"], __type: "s32"),
                        E.e("clear_music_num", profile[rg]["record_max_clear_music_num"],
                          __type: "s32"
                        ),
                        E.e("full_music_num", profile[rg]["record_max_full_music_num"],
                          __type: "s32"
                        ),
                        E.e("exce_music_num", profile[rg]["record_max_exce_music_num"],
                          __type: "s32"
                        ),
                        E.e("clear_seq_num", profile[rg]["record_max_clear_seq_num"],
                          __type: "s32"
                        ),
                        E.e("classic_all_skill", profile[rg]["record_max_classic_all_skill"],
                          __type: "s32"
                        )
                      ]),
                      E.e("diff_record", [
                        E.e("diff_100_nr", profile[rg]["record_diff_100_nr"], __type: "s32"),
                        E.e("diff_150_nr", profile[rg]["record_diff_150_nr"], __type: "s32"),
                        E.e("diff_200_nr", profile[rg]["record_diff_200_nr"], __type: "s32"),
                        E.e("diff_250_nr", profile[rg]["record_diff_250_nr"], __type: "s32"),
                        E.e("diff_300_nr", profile[rg]["record_diff_300_nr"], __type: "s32"),
                        E.e("diff_350_nr", profile[rg]["record_diff_350_nr"], __type: "s32"),
                        E.e("diff_400_nr", profile[rg]["record_diff_400_nr"], __type: "s32"),
                        E.e("diff_450_nr", profile[rg]["record_diff_450_nr"], __type: "s32"),
                        E.e("diff_500_nr", profile[rg]["record_diff_500_nr"], __type: "s32"),
                        E.e("diff_550_nr", profile[rg]["record_diff_550_nr"], __type: "s32"),
                        E.e("diff_600_nr", profile[rg]["record_diff_600_nr"], __type: "s32"),
                        E.e("diff_650_nr", profile[rg]["record_diff_650_nr"], __type: "s32"),
                        E.e("diff_700_nr", profile[rg]["record_diff_700_nr"], __type: "s32"),
                        E.e("diff_750_nr", profile[rg]["record_diff_750_nr"], __type: "s32"),
                        E.e("diff_800_nr", profile[rg]["record_diff_800_nr"], __type: "s32"),
                        E.e("diff_850_nr", profile[rg]["record_diff_850_nr"], __type: "s32"),
                        E.e("diff_900_nr", profile[rg]["record_diff_900_nr"], __type: "s32"),
                        E.e("diff_950_nr", profile[rg]["record_diff_950_nr"], __type: "s32"),
                        E.e("diff_100_clear", profile[rg]["record_diff_100_clear"], __type: "s32"),
                        E.e("diff_150_clear", profile[rg]["record_diff_150_clear"], __type: "s32"),
                        E.e("diff_200_clear", profile[rg]["record_diff_200_clear"], __type: "s32"),
                        E.e("diff_250_clear", profile[rg]["record_diff_250_clear"], __type: "s32"),
                        E.e("diff_300_clear", profile[rg]["record_diff_300_clear"], __type: "s32"),
                        E.e("diff_350_clear", profile[rg]["record_diff_350_clear"], __type: "s32"),
                        E.e("diff_400_clear", profile[rg]["record_diff_400_clear"], __type: "s32"),
                        E.e("diff_450_clear", profile[rg]["record_diff_450_clear"], __type: "s32"),
                        E.e("diff_500_clear", profile[rg]["record_diff_500_clear"], __type: "s32"),
                        E.e("diff_550_clear", profile[rg]["record_diff_550_clear"], __type: "s32"),
                        E.e("diff_600_clear", profile[rg]["record_diff_600_clear"], __type: "s32"),
                        E.e("diff_650_clear", profile[rg]["record_diff_650_clear"], __type: "s32"),
                        E.e("diff_700_clear", profile[rg]["record_diff_700_clear"], __type: "s32"),
                        E.e("diff_750_clear", profile[rg]["record_diff_750_clear"], __type: "s32"),
                        E.e("diff_800_clear", profile[rg]["record_diff_800_clear"], __type: "s32"),
                        E.e("diff_850_clear", profile[rg]["record_diff_850_clear"], __type: "s32"),
                        E.e("diff_900_clear", profile[rg]["record_diff_900_clear"], __type: "s32"),
                        E.e("diff_950_clear", profile[rg]["record_diff_950_clear"], __type: "s32")
                      ])
                    ])
                  end)
                ),
                E.e("groove", [
                  E.e("extra_gauge", pg["groove_extra_gauge"], __type: "s32"),
                  E.e("encore_gauge", pg["groove_encore_gauge"], __type: "s32"),
                  E.e("encore_cnt", pg["groove_encore_cnt"], __type: "s32"),
                  E.e("encore_success", pg["groove_encore_success"], __type: "s32"),
                  E.e("unlock_point", pg["groove_unlock_point"], __type: "s32")
                ]),
                E.e("finish", 1, __type: "bool")
              ],
            no: no
          )
        )
      )

    Core.send_response(conn, info, response)
  end

  defp rivaldata([]), do: E.e("rivaldata")

  defp rivaldata(rivals) do
    E.e(
      "rivaldata",
      rivals
      |> Enum.with_index(1)
      |> Enum.map(fn {r, r_idx} ->
        E.e("rival", [
          E.e("did", 1, __type: "s32"),
          E.e("name", "", __type: "str"),
          E.e("active_index", r_idx, __type: "s32"),
          E.e("refid", r, __type: "str")
        ])
      end)
    )
  end
end
