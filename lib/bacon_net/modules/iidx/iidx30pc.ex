defmodule BaconNet.Modules.Iidx.Iidx30pc do
  @moduledoc "Port of modules/iidx/iidx30pc.py."

  import Bitwise

  alias BaconNet.{Config, Core, DB, E, XNode}

  def routes do
    %{
      prefix: "/local2",
      tag: "local2",
      handlers: [
        {"IIDX30pc", "get", :iidx30pc_get},
        {"IIDX30pc", "common", :iidx30pc_common},
        {"IIDX30pc", "save", :iidx30pc_save},
        {"IIDX30pc", "visit", :iidx30pc_visit},
        {"IIDX30pc", "reg", :iidx30pc_reg},
        {"IIDX30pc", "getLaneGachaTicket", :iidx30pc_getlanegachaticket},
        {"IIDX30pc", "consumeLaneGachaTicket", :iidx30pc_consumelanegachaticket},
        {"IIDX30pc", "drawLaneGacha", :iidx30pc_drawlanegacha},
        {"IIDX30pc", "eaappliresult", :iidx30pc_eaappliresult},
        {"IIDX30pc", "playstart", :iidx30pc_playstart},
        {"IIDX30pc", "playend", :iidx30pc_playend},
        {"IIDX30pc", "delete", :iidx30pc_delete},
        {"IIDX30pc", "logout", :iidx30pc_logout}
      ]
    }
  end

  defp get_profile(cid), do: DB.get("iidx_profile", %{"card" => cid})

  defp get_profile_by_id(iidx_id), do: DB.get("iidx_profile", %{"iidx_id" => iidx_id})

  defp get_game_profile(cid, game_version) do
    profile = get_profile(cid)

    get_in(profile, ["version", to_string(game_version)])
  end

  defp get_game_profile_by_id(iidx_id, game_version) do
    profile = get_profile_by_id(iidx_id)

    get_in(profile, ["version", to_string(game_version)])
  end

  defp get_id_from_profile(cid) do
    profile = DB.get("iidx_profile", %{"card" => cid})

    djid = Integer.to_string(profile["iidx_id"]) |> String.pad_leading(8, "0")
    djid_split = String.slice(djid, 0, 4) <> "-" <> String.slice(djid, 4, 4)

    {profile["iidx_id"], djid_split}
  end

  defp calculate_folder_mask(profile) do
    Map.get(profile, "_show_category_grade", 0) <<< 0 |||
      Map.get(profile, "_show_category_status", 0) <<< 1 |||
      Map.get(profile, "_show_category_difficulty", 0) <<< 2 |||
      Map.get(profile, "_show_category_alphabet", 0) <<< 3 |||
      Map.get(profile, "_show_category_rival_play", 0) <<< 4 |||
      Map.get(profile, "_show_category_rival_winlose", 0) <<< 6 |||
      Map.get(profile, "_show_rival_shop_info", 0) <<< 7 |||
      Map.get(profile, "_hide_play_count", 0) <<< 8 |||
      Map.get(profile, "_show_score_graph_cutin", 0) <<< 9 |||
      Map.get(profile, "_classic_hispeed", 0) <<< 10 |||
      Map.get(profile, "_hide_iidx_id", 0) <<< 12
  end

  def iidx30pc_get(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    node = Core.module_node(info)
    cid = XNode.attr(node, "cid")
    profile = get_game_profile(cid, game_version)
    {djid, djid_split} = get_id_from_profile(cid)

    rival_ids = [
      Map.get(profile, "sp_rival_1_iidx_id", 0),
      Map.get(profile, "sp_rival_2_iidx_id", 0),
      Map.get(profile, "sp_rival_3_iidx_id", 0),
      Map.get(profile, "sp_rival_4_iidx_id", 0),
      Map.get(profile, "sp_rival_5_iidx_id", 0),
      Map.get(profile, "sp_rival_6_iidx_id", 0),
      Map.get(profile, "dp_rival_1_iidx_id", 0),
      Map.get(profile, "dp_rival_2_iidx_id", 0),
      Map.get(profile, "dp_rival_3_iidx_id", 0),
      Map.get(profile, "dp_rival_4_iidx_id", 0),
      Map.get(profile, "dp_rival_5_iidx_id", 0),
      Map.get(profile, "dp_rival_6_iidx_id", 0)
    ]

    rivals =
      rival_ids
      |> Enum.with_index()
      |> Enum.filter(fn {r, _idx} -> r != 0 end)
      |> Enum.map(fn {r, idx} ->
        rival_profile = get_game_profile_by_id(r, game_version)
        rdjid = Integer.to_string(r) |> String.pad_leading(8, "0")
        rdjid_split = String.slice(rdjid, 0, 4) <> "-" <> String.slice(rdjid, 4, 4)

        %{
          spdp: if(idx < 6, do: 1, else: 2),
          djid: rdjid,
          djid_split: rdjid_split,
          djname: rival_profile["djname"],
          region: rival_profile["region"],
          sa: rival_profile["sach"],
          sg: rival_profile["grade_single"],
          da: rival_profile["dach"],
          dg: rival_profile["grade_double"],
          body: rival_profile["body"],
          face: rival_profile["face"],
          hair: rival_profile["hair"],
          hand: rival_profile["hand"],
          head: rival_profile["head"]
        }
      end)

    response =
      E.e("response",
        E.e("IIDX30pc", [
          E.e("pcdata",
            d_auto_adjust: profile["d_auto_adjust"],
            d_auto_scrach: profile["d_auto_scrach"],
            d_camera_layout: profile["d_camera_layout"],
            d_disp_judge: profile["d_disp_judge"],
            d_exscore: profile["d_exscore"],
            d_gauge_disp: profile["d_gauge_disp"],
            d_ghost_score: profile["d_ghost_score"],
            d_gno: profile["d_gno"],
            d_graph_score: profile["d_graph_score"],
            d_gtype: profile["d_gtype"],
            d_hispeed: profile["d_hispeed"],
            d_judge: profile["d_judge"],
            d_judgeAdj: profile["d_judgeAdj"],
            d_lane_brignt: profile["d_lane_brignt"],
            d_liflen: profile["d_liflen"],
            d_notes: profile["d_notes"],
            d_opstyle: profile["d_opstyle"],
            d_pace: profile["d_pace"],
            d_sdlen: profile["d_sdlen"],
            d_sdtype: profile["d_sdtype"],
            d_sorttype: profile["d_sorttype"],
            d_sub_gno: profile["d_sub_gno"],
            d_timing: profile["d_timing"],
            d_timing_split: profile["d_timing_split"],
            d_tsujigiri_disp: profile["d_tsujigiri_disp"],
            d_tune: profile["d_tune"],
            d_visualization: profile["d_visualization"],
            dach: profile["dach"],
            dp_opt: profile["dp_opt"],
            dp_opt2: profile["dp_opt2"],
            dpnum: profile["dpnum"],
            gpos: profile["gpos"],
            id: djid,
            idstr: djid_split,
            mode: profile["mode"],
            name: profile["djname"],
            ngrade: profile["ngrade"],
            pid: profile["region"],
            pmode: profile["pmode"],
            rtype: profile["rtype"],
            s_auto_adjust: profile["s_auto_adjust"],
            s_auto_scrach: profile["s_auto_scrach"],
            s_camera_layout: profile["s_camera_layout"],
            s_disp_judge: profile["s_disp_judge"],
            s_exscore: profile["s_exscore"],
            s_gauge_disp: profile["s_gauge_disp"],
            s_ghost_score: profile["s_ghost_score"],
            s_gno: profile["s_gno"],
            s_graph_score: profile["s_graph_score"],
            s_gtype: profile["s_gtype"],
            s_hispeed: profile["s_hispeed"],
            s_judge: profile["s_judge"],
            s_judgeAdj: profile["s_judgeAdj"],
            s_lane_brignt: profile["s_lane_brignt"],
            s_liflen: profile["s_liflen"],
            s_notes: profile["s_notes"],
            s_opstyle: profile["s_opstyle"],
            s_pace: profile["s_pace"],
            s_sdlen: profile["s_sdlen"],
            s_sdtype: profile["s_sdtype"],
            s_sorttype: profile["s_sorttype"],
            s_sub_gno: profile["s_sub_gno"],
            s_timing: profile["s_timing"],
            s_timing_split: profile["s_timing_split"],
            s_tsujigiri_disp: profile["s_tsujigiri_disp"],
            s_tune: profile["s_tune"],
            s_visualization: profile["s_visualization"],
            sach: profile["sach"],
            sp_opt: profile["sp_opt"],
            spnum: profile["spnum"]
          ),
          E.e(
            "qprodata",
            [
              profile["head"],
              profile["hair"],
              profile["face"],
              profile["hand"],
              profile["body"]
            ],
            __type: "u32",
            __size: 5 * 4
          ),
          E.e(
            "skin",
            [
              profile["frame"],
              profile["turntable"],
              profile["explosion"],
              profile["bgm"],
              calculate_folder_mask(profile),
              profile["sudden"],
              profile["judge_pos"],
              profile["categoryvoice"],
              profile["note"],
              profile["fullcombo"],
              profile["keybeam"],
              profile["judgestring"],
              -1,
              profile["soundpreview"],
              profile["grapharea"],
              profile["effector_lock"],
              profile["effector_type"],
              profile["explosion_size"],
              profile["alternate_hcn"],
              profile["kokokara_start"]
            ],
            __type: "s16"
          ),
          # required for rivals to load after switching spdp in music select
          E.e("spdp_rival", flg: -1),
          E.e(
            "rlist",
            Enum.map(rivals, fn r ->
              E.e(
                "rival",
                [
                  E.e("is_robo", 0, __type: "bool"),
                  E.e("shop", name: Config.arcade()),
                  E.e("qprodata",
                    body: r.body,
                    face: r.face,
                    hair: r.hair,
                    hand: r.hand,
                    head: r.head
                  )
                ],
                da: r.da,
                dg: r.dg,
                djname: r.djname,
                id: r.djid,
                id_str: r.djid_split,
                pid: r.region,
                sa: r.sa,
                sg: r.sg,
                spdp: r.spdp
              )
            end)
          ),
          E.e("ir_data"),
          E.e("secret_course_data"),
          E.e("deller", deller: profile["deller"], rate: 0),
          E.e("secret", [
            E.e("flg1", Map.get(profile, "secret_flg1", [-1, -1, -1]), __type: "s64"),
            E.e("flg2", Map.get(profile, "secret_flg2", [-1, -1, -1]), __type: "s64"),
            E.e("flg3", Map.get(profile, "secret_flg3", [-1, -1, -1]), __type: "s64"),
            E.e("flg4", Map.get(profile, "secret_flg4", [-1, -1, -1]), __type: "s64")
          ]),
          E.e("join_shop", join_cflg: 1, join_id: 10, join_name: Config.arcade(), joinflg: 1),
          E.e("leggendaria",
            E.e("flg1", Map.get(profile, "leggendaria_flg1", [-1, -1, -1]), __type: "s64")
          ),
          E.e(
            "grade",
            Enum.map(profile["grade_values"], fn x -> E.e("g", x, __type: "u8") end),
            dgid: profile["grade_double"],
            sgid: profile["grade_single"]
          ),
          E.e("world_tourism_secret_flg", [
            E.e("flg1", Map.get(profile, "wt_flg1", [-1, -1, -1]), __type: "s64"),
            E.e("flg2", Map.get(profile, "wt_flg2", [-1, -1, -1]), __type: "s64")
          ]),
          E.e(
            "world_tourism",
            for i <- 0..15 do
              # set to 49 to see WT folders, 50 is completed/hidden
              E.e("tour_data",
                tour_id: i,
                progress: 50
              )
            end
          ),
          E.e(
            "lightning_setting",
            [
              E.e("slider", Map.get(profile, "lightning_setting_slider", List.duplicate(0, 7)),
                __type: "s32"
              ),
              E.e("light", Map.get(profile, "lightning_setting_light", List.duplicate(1, 10)),
                __type: "bool"
              ),
              E.e("concentration", Map.get(profile, "lightning_setting_concentration", 0),
                __type: "bool"
              )
            ],
            headphone_vol: Map.get(profile, "lightning_setting_headphone_vol", 0),
            resistance_sp_left: Map.get(profile, "lightning_setting_resistance_sp_left", 0),
            resistance_sp_right: Map.get(profile, "lightning_setting_resistance_sp_right", 0),
            resistance_dp_left: Map.get(profile, "lightning_setting_resistance_dp_left", 0),
            resistance_dp_right: Map.get(profile, "lightning_setting_resistance_dp_right", 0),
            skin_0: Map.get(profile, "lightning_setting_skin_0", 0),
            flg_skin_0: Map.get(profile, "lightning_setting_flg_skin_0", 0)
          ),
          E.e(
            "arena_data",
            [
              E.e("achieve_data",
                play_style: 0,
                arena_class: 19,
                rating_value: 90,
                win_count: 0,
                now_winning_streak_count: 0,
                best_winning_streak_count: 0,
                perfect_win_count: 0,
                counterattack_num: 0,
                mission_clear_num: 0
              ),
              E.e("achieve_data",
                play_style: 1,
                arena_class: 19,
                rating_value: 90,
                win_count: 0,
                now_winning_streak_count: 0,
                best_winning_streak_count: 0,
                perfect_win_count: 0,
                counterattack_num: 0,
                mission_clear_num: 0
              ),
              E.e("cube_data",
                cube: 200,
                season_id: 0
              ),
              E.e("ranker_data",
                play_style: 0,
                pref_id: 0,
                rank_num: Enum.random([:rand.uniform(5), 573])
              ),
              E.e("ranker_data",
                play_style: 1,
                pref_id: 0,
                rank_num: Enum.random([:rand.uniform(5), 573])
              ),
              E.e("lose_data",
                play_style: 0,
                lose_value: 0
              ),
              E.e("lose_data",
                play_style: 1,
                lose_value: 0
              ),
              E.e(
                "chat_data",
                [
                  E.e("is_chat_0", 1, __type: "bool"),
                  E.e("is_chat_1", 1, __type: "bool"),
                  E.e("is_chat_2", 1, __type: "bool"),
                  E.e("is_chat_3", 1, __type: "bool")
                ],
                chat_type_0: "hi",
                chat_type_1: "やあ",
                chat_type_2: "こんにちは",
                chat_type_3: "おす"
              ),
              E.e("tendency",
                play_style: 0,
                rank0: 1,
                rank1: 2,
                rank2: 3,
                rank3: 4,
                rank4: 3,
                rank5: 1
              ),
              E.e("player_kind_data",
                kind: Enum.random([:rand.uniform(14) - 1, 0])
              ),
              E.e("setting",
                stats_type: 0
              ),
              E.e("qpro_motion",
                motion_0: 1,
                motion_1: 2,
                motion_2: 3
              )
            ],
            play_num: 6,
            play_num_dp: 3,
            play_num_sp: 3,
            prev_best_class_sp: 18,
            prev_best_class_dp: 18
          ),
          E.e("follow_data"),
          E.e("classic_course_data"),
          E.e("bind_eaappli"),
          E.e("ea_premium_course"),
          E.e("enable_qr_reward"),
          E.e("nostalgia_open"),
          E.e("language_setting", language: profile["language_setting"]),
          E.e("movie_agreement", agreement_version: Map.get(profile, "movie_agreement", 0)),
          E.e("bpl_virtual"),
          E.e("lightning_play_data",
            spnum: profile["lightning_play_data_spnum"],
            dpnum: profile["lightning_play_data_dpnum"]
          ),
          E.e("weekly",
            mid: -1,
            wid: 1
          ),
          E.e("packinfo",
            music_0: -1,
            music_1: -1,
            music_2: -1,
            pack_id: 1
          ),
          E.e("kac_entry_info", [
            E.e("enable_kac_deller"),
            E.e("disp_kac_mark"),
            E.e("open_kac_common_music"),
            E.e("open_kac_new_a12_music"),
            E.e("is_kac_entry"),
            E.e("is_kac_evnet_entry")
          ]),
          E.e("orb_data", rest_orb: 100, present_orb: 100),
          E.e("visitor", anum: 1, pnum: 2, snum: 1, vs_flg: 1),
          E.e("tonjyutsu", black_pass: -1, platinum_pass: -1),
          E.e("pay_per_use", item_num: 99),
          E.e("old_linkage_secret_flg",
            song_battle: -1
          ),
          E.e("floor_infection4", music_list: -1),
          E.e("bemani_vote", music_list: -1),
          E.e("bemani_janken_meeting", music_list: -1),
          E.e("bemani_rush", music_list_ichika: -1, music_list_nono: -1),
          E.e("ultimate_mobile_link", E.e("link_flag"), music_list: -1),
          E.e("bemani_musiq_fes", music_list: -1),
          E.e("busou_linkage", music_list: -1),
          E.e("busou_linkage_2", music_list: -1),
          E.e("valkyrie_linkage", music_list_1: -1, music_list_2: -1, music_list_3: -1),
          E.e("bemani_song_battle", music_list: -1),
          E.e("bemani_mixup", music_list: -1),
          E.e("ccj_linkage", music_list: -1),
          E.e("triple_tribe", music_list: -1),
          E.e(
            "achievements",
            E.e("trophy", Map.get(profile, "achievements_trophy", []) |> Enum.take(10),
              __type: "s64"
            ),
            pack: Map.get(profile, "achievements_pack_id", 0),
            pack_comp: Map.get(profile, "achievements_pack_comp", 0),
            last_weekly: Map.get(profile, "achievements_last_weekly", 0),
            weekly_num: Map.get(profile, "achievements_weekly_num", 0),
            visit_flg: Map.get(profile, "achievements_visit_flg", 0),
            rival_crush: 0
          ),
          E.e(
            "notes_radar",
            E.e("radar_score", profile["notes_radar_single"], __type: "s32"),
            style: 0
          ),
          E.e(
            "notes_radar",
            E.e("radar_score", profile["notes_radar_double"], __type: "s32"),
            style: 1
          ),
          E.e(
            "dj_rank",
            [
              E.e("rank", profile["dj_rank_single_rank"], __type: "s32"),
              E.e("point", profile["dj_rank_single_point"], __type: "s32")
            ],
            style: 0
          ),
          E.e(
            "dj_rank",
            [
              E.e("rank", profile["dj_rank_double_rank"], __type: "s32"),
              E.e("point", profile["dj_rank_double_point"], __type: "s32")
            ],
            style: 1
          ),
          E.e(
            "step",
            E.e("is_track_ticket", profile["stepup_is_track_ticket"], __type: "bool"),
            dp_fluctuation: profile["stepup_dp_fluctuation"],
            dp_level: profile["stepup_dp_level"],
            dp_mplay: profile["stepup_dp_mplay"],
            enemy_damage: profile["stepup_enemy_damage"],
            enemy_defeat_flg: profile["stepup_enemy_defeat_flg"],
            mission_clear_num: profile["stepup_mission_clear_num"],
            progress: profile["stepup_progress"],
            sp_fluctuation: profile["stepup_sp_fluctuation"],
            sp_level: profile["stepup_sp_level"],
            sp_mplay: profile["stepup_sp_mplay"],
            tips_read_list: profile["stepup_tips_read_list"],
            total_point: profile["stepup_total_point"]
          ),
          E.e("tsujigiri", total_num_sp: 287, total_num_dp: 286),
          E.e("tsujigiri_hidden_chara", [
            E.e("appearance_info",
              appearance_id: 1,
              music_0: -1,
              music_1: -1,
              music_2: -1,
              chara_0: -1,
              chara_1: -1,
              chara_2: -1
            ),
            E.e("defeat", defeat_flg: 0),
            E.e("total_defeat",
              E.e("chara",
                id: 0,
                num: 0
              )
            )
          ]),
          E.e("skin_customize_flg",
            skin_frame_flg: profile["skin_customize_flag_frame"],
            skin_bgm_flg: profile["skin_customize_flag_bgm"],
            skin_lane_flg3: profile["skin_customize_flag_lane"]
          ),
          E.e("badge", [
            # Base
            E.e("badge_data",
              category_id: 1,
              badge_flg_id: 23,
              badge_flg: 554_321
            ),
            E.e("badge_data",
              category_id: 1,
              badge_flg_id: 11,
              badge_flg: 554_321
            ),
            E.e(
              "badge_equip",
              E.e("equip_flg", 1, __type: "bool"),
              category_id: 1,
              badge_flg_id: 23,
              index: 5,
              slot: 0
            ),
            E.e(
              "badge_equip",
              E.e("equip_flg", 1, __type: "bool"),
              category_id: 1,
              badge_flg_id: 11,
              index: 5,
              slot: 4
            ),
            # Class
            E.e("badge_data",
              category_id: 2,
              badge_flg_id: 0,
              badge_flg: 1_919_191_919_19
            ),
            E.e(
              "badge_equip",
              E.e("equip_flg", 1, __type: "bool"),
              category_id: 2,
              badge_flg_id: 0,
              index: 2,
              slot: 3
            ),
            E.e(
              "badge_equip",
              E.e("equip_flg", 1, __type: "bool"),
              category_id: 2,
              badge_flg_id: 0,
              index: 5,
              slot: 1
            ),
            # Radar Rank
            E.e("badge_data",
              category_id: 7,
              badge_flg_id: 1,
              badge_flg: 1_010_101_010
            ),
            E.e(
              "badge_equip",
              E.e("equip_flg", 1, __type: "bool"),
              category_id: 7,
              badge_flg_id: 1,
              index: 2,
              slot: 2
            )
          ])
        ])
      )

    Core.send_response(conn, info, response)
  end

  def iidx30pc_common(conn) do
    {info, conn} = Core.process_request(conn)
    client_host = conn.remote_ip |> :inet.ntoa() |> to_string()

    response =
      E.e("response",
        E.e(
          "IIDX30pc",
          [
            E.e(
              "monthly_mranking",
              [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
              __type: "u16"
            ),
            E.e(
              "total_mranking",
              [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
              __type: "u16"
            ),
            E.e("kac_mid", [-1, -1, -1, -1, -1], __type: "s32"),
            E.e("kac_clid", [2, 2, 2, 2, 2], __type: "s32"),
            E.e("ir", beat: 3),
            E.e("cm", compo: "cm_ultimate", folder: "cm_ultimate", id: 0),
            E.e("tdj_cm", [
              E.e("cm", filename: "cm_bn_001", id: 0),
              E.e("cm", filename: "cm_bn_002", id: 1),
              E.e("cm", filename: "event_bn_001", id: 2),
              E.e("cm", filename: "event_bn_004", id: 3),
              E.e("cm", filename: "event_bn_006", id: 4),
              E.e("cm", filename: "fipb_001", id: 5),
              E.e("cm", filename: "year_bn_004", id: 6),
              E.e("cm", filename: "year_bn_005", id: 7),
              E.e("cm", filename: "year_bn_006_2", id: 8),
              E.e("cm", filename: "year_bn_007", id: 9)
            ]),
            E.e("movie_agreement", version: 1),
            E.e("license", "None", __type: "str"),
            E.e("file_recovery", url: Config.ip()),
            # use https://github.com/bookqaq/010-record-api
            E.e("movie_upload", url: "http://#{client_host}:4399/movie/"),
            E.e("escape_package_info"),
            # disable event
            E.e("boss", phase: 0),
            E.e("vip_pass_black"),
            E.e("eisei", open: 1),
            E.e("deller_bonus", open: 1),
            E.e("newsong_another", open: 1),
            E.e("expert_secret_full_open"),
            E.e("eaorder_phase", phase: -1),
            E.e("common_evnet", flg: -1),
            # TODO: Figure out range
            E.e("system_voice_phase", phase: :rand.uniform(10)),
            E.e("extra_boss_event", phase: 6),
            E.e("event1_phase", phase: 4),
            E.e("premium_area_news", open: 1),
            E.e("premium_area_qpro", open: 1),
            E.e("play_video"),
            E.e("world_tourism", open_list: 1),
            E.e("bpl_battle", phase: 1),
            E.e("display_asio_logo"),
            E.e("lane_gacha"),
            E.e("tourism_booster"),
            E.e("ameto_event")
          ],
          expire: 600
        )
      )

    Core.send_response(conn, info, response)
  end

  def iidx30pc_save(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    node = Core.module_node(info)
    xid = XNode.attr(node, "iidxid") |> String.to_integer()
    cid = XNode.attr(node, "cid")
    clt = XNode.attr(node, "cltype") |> String.to_integer()

    profile = get_profile(cid)
    game_profile = get_in(profile, ["version", to_string(game_version)]) || %{}

    game_profile =
      Enum.reduce(
        [
          "d_auto_adjust",
          "d_auto_scrach",
          "d_camera_layout",
          "d_disp_judge",
          "d_gauge_disp",
          "d_ghost_score",
          "d_gno",
          "d_graph_score",
          "d_gtype",
          "d_hispeed",
          "d_judge",
          "d_judgeAdj",
          "d_lane_brignt",
          "d_notes",
          "d_opstyle",
          "d_pace",
          "d_sdlen",
          "d_sdtype",
          "d_sorttype",
          "d_sub_gno",
          "d_timing",
          "d_timing_split",
          "d_tsujigiri_disp",
          "d_visualization",
          "dp_opt",
          "dp_opt2",
          "gpos",
          "mode",
          "ngrade",
          "pmode",
          "rtype",
          "s_auto_adjust",
          "s_auto_scrach",
          "s_camera_layout",
          "s_disp_judge",
          "s_gauge_disp",
          "s_ghost_score",
          "s_gno",
          "s_graph_score",
          "s_gtype",
          "s_hispeed",
          "s_judge",
          "s_judgeAdj",
          "s_lane_brignt",
          "s_notes",
          "s_opstyle",
          "s_pace",
          "s_sdlen",
          "s_sdtype",
          "s_sorttype",
          "s_sub_gno",
          "s_timing",
          "s_timing_split",
          "s_tsujigiri_disp",
          "s_visualization",
          "sp_opt"
        ],
        game_profile,
        fn k, gp ->
          case XNode.attr(node, k) do
            nil -> gp
            v -> Map.put(gp, k, v)
          end
        end
      )

    game_profile =
      Enum.reduce(
        [
          {"d_liflen", "d_lift"},
          {"dach", "d_achi"},
          {"s_liflen", "s_lift"},
          {"sach", "s_achi"}
        ],
        game_profile,
        fn {dst, src}, gp ->
          case XNode.attr(node, src) do
            nil -> gp
            v -> Map.put(gp, dst, v)
          end
        end
      )

    game_profile =
      case XNode.child(node, "lightning_setting") do
        nil ->
          game_profile

        lightning_setting ->
          gp =
            Enum.reduce(
              [
                "headphone_vol",
                "resistance_dp_left",
                "resistance_dp_right",
                "resistance_sp_left",
                "resistance_sp_right"
              ],
              game_profile,
              fn k, acc ->
                Map.put(
                  acc,
                  "lightning_setting_" <> k,
                  XNode.attr(lightning_setting, k) |> String.to_integer()
                )
              end
            )

          gp =
            case XNode.child(lightning_setting, "slider") do
              nil -> gp
              slider -> Map.put(gp, "lightning_setting_slider", XNode.text_ints(slider))
            end

          gp =
            case XNode.child(lightning_setting, "light") do
              nil -> gp
              light -> Map.put(gp, "lightning_setting_light", XNode.text_ints(light))
            end

          case XNode.child(lightning_setting, "concentration") do
            nil -> gp
            concentration -> Map.put(gp, "lightning_setting_concentration", String.to_integer(concentration.text))
          end
      end

    game_profile =
      case XNode.child(node, "movie_agreement") do
        nil ->
          game_profile

        movie_agreement ->
          case XNode.attr(movie_agreement, "agreement_version") do
            nil -> game_profile
            v -> Map.put(game_profile, "movie_agreement", String.to_integer(v))
          end
      end

    game_profile =
      case XNode.child(node, "movie_setting") do
        nil ->
          game_profile

        movie_setting ->
          case XNode.child(movie_setting, "hide_name") do
            nil -> game_profile
            hide_name -> Map.put(game_profile, "hide_name", String.to_integer(hide_name.text))
          end
      end

    game_profile =
      case XNode.child(node, "lightning_customize_flg") do
        nil ->
          game_profile

        lightning_customize_flg ->
          Enum.reduce(["flg_skin_0"], game_profile, fn k, gp ->
            Map.put(
              gp,
              "lightning_setting_" <> k,
              XNode.attr(lightning_customize_flg, k) |> String.to_integer()
            )
          end)
      end

    game_profile =
      case XNode.child(node, "secret") do
        nil ->
          game_profile

        secret ->
          Enum.reduce(["flg1", "flg2", "flg3", "flg4"], game_profile, fn k, gp ->
            case XNode.child(secret, k) do
              nil -> gp
              flg -> Map.put(gp, "secret_" <> k, XNode.text_ints(flg))
            end
          end)
      end

    game_profile =
      case XNode.child(node, "leggendaria") do
        nil ->
          game_profile

        leggendaria ->
          Enum.reduce(["flg1"], game_profile, fn k, gp ->
            case XNode.child(leggendaria, k) do
              nil -> gp
              flg -> Map.put(gp, "leggendaria_" <> k, XNode.text_ints(flg))
            end
          end)
      end

    game_profile =
      case XNode.child(node, "step") do
        nil ->
          game_profile

        step ->
          gp =
            Enum.reduce(
              [
                "dp_fluctuation",
                "dp_level",
                "dp_mplay",
                "enemy_damage",
                "enemy_defeat_flg",
                "mission_clear_num",
                "progress",
                "sp_fluctuation",
                "sp_level",
                "sp_mplay",
                "tips_read_list",
                "total_point"
              ],
              game_profile,
              fn k, acc ->
                Map.put(acc, "stepup_" <> k, XNode.attr(step, k) |> String.to_integer())
              end
            )

          case XNode.child(step, "is_track_ticket") do
            nil -> gp
            is_track_ticket -> Map.put(gp, "stepup_is_track_ticket", String.to_integer(is_track_ticket.text))
          end
      end

    game_profile =
      Enum.reduce(XNode.children(node, "dj_rank"), game_profile, fn dj_rank, gp ->
        style = XNode.attr(dj_rank, "style") |> String.to_integer()
        style_name = Enum.fetch!(["single", "double"], style)

        rank = XNode.child(dj_rank, "rank")
        point = XNode.child(dj_rank, "point")

        gp
        |> Map.put("dj_rank_" <> style_name <> "_rank", XNode.text_ints(rank))
        |> Map.put("dj_rank_" <> style_name <> "_point", XNode.text_ints(point))
      end)

    game_profile =
      Enum.reduce(XNode.children(node, "notes_radar"), game_profile, fn notes_radar, gp ->
        style = XNode.attr(notes_radar, "style") |> String.to_integer()
        style_name = Enum.fetch!(["single", "double"], style)
        score = XNode.child(notes_radar, "radar_score")

        Map.put(gp, "notes_radar_" <> style_name, XNode.text_ints(score))
      end)

    game_profile =
      case XNode.child(node, "achievements") do
        nil ->
          game_profile

        achievements ->
          gp =
            Enum.reduce(
              [
                "last_weekly",
                "pack_comp",
                "pack_flg",
                "pack_id",
                "play_pack",
                "visit_flg",
                "weekly_num"
              ],
              game_profile,
              fn k, acc ->
                Map.put(acc, "achievements_" <> k, XNode.attr(achievements, k) |> String.to_integer())
              end
            )

          case XNode.child(achievements, "trophy") do
            nil -> gp
            trophy -> Map.put(gp, "achievements_trophy", XNode.text_ints(trophy))
          end
      end

    profile =
      case XNode.child(node, "grade") do
        nil ->
          profile

        grade ->
          grade_values =
            Enum.map(XNode.children(grade, "g"), fn g -> XNode.text_ints(g) end)

          profile
          |> Map.put("grade_single", XNode.attr(grade, "sgid") |> String.to_integer())
          |> Map.put("grade_double", XNode.attr(grade, "dgid") |> String.to_integer())
          |> Map.put("grade_values", grade_values)
      end

    deller_amount = Map.get(game_profile, "deller", 0)

    deller_amount =
      case XNode.child(node, "deller") do
        nil -> deller_amount
        deller -> XNode.attr(deller, "deller") |> String.to_integer()
      end

    game_profile = Map.put(game_profile, "deller", deller_amount)

    game_profile =
      case XNode.child(node, "language_setting") do
        nil ->
          game_profile

        language ->
          Map.put(game_profile, "language_setting", XNode.attr(language, "language") |> String.to_integer())
      end

    game_profile =
      game_profile
      |> Map.put("spnum", Map.get(game_profile, "spnum", 0) + if(clt == 0, do: 1, else: 0))
      |> Map.put("dpnum", Map.get(game_profile, "dpnum", 0) + if(clt == 1, do: 1, else: 0))

    game_profile =
      if info.model == "TDJ" do
        game_profile
        |> Map.put(
          "lightning_play_data_spnum",
          Map.get(game_profile, "lightning_play_data_spnum", 0) + if(clt == 0, do: 1, else: 0)
        )
        |> Map.put(
          "lightning_play_data_dpnum",
          Map.get(game_profile, "lightning_play_data_dpnum", 0) + if(clt == 1, do: 1, else: 0)
        )
      else
        game_profile
      end

    profile = put_in(profile, ["version", to_string(game_version)], game_profile)

    DB.upsert("iidx_profile", profile, %{"card" => cid})

    response = E.e("response", E.e("IIDX30pc", iidxid: xid, cltype: clt))

    Core.send_response(conn, info, response)
  end

  def iidx30pc_visit(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e("response",
        E.e("IIDX30pc",
          aflg: 1,
          anum: 1,
          pflg: 1,
          pnum: 1,
          sflg: 1,
          snum: 1
        )
      )

    Core.send_response(conn, info, response)
  end

  def iidx30pc_reg(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    node = Core.module_node(info)
    cid = XNode.attr(node, "cid")
    name = XNode.attr(node, "name")
    pid = XNode.attr(node, "pid")

    all_profiles_for_card =
      DB.get("iidx_profile", %{"card" => cid}) || %{"card" => cid, "version" => %{}}

    all_profiles_for_card =
      if Map.has_key?(all_profiles_for_card, "iidx_id") do
        all_profiles_for_card
      else
        iidx_id = :rand.uniform(90_000_000) + 9_999_999
        Map.put(all_profiles_for_card, "iidx_id", iidx_id)
      end

    version_profile = %{
      "game_version" => game_version,
      "djname" => name,
      "region" => String.to_integer(pid),
      "head" => 0,
      "hair" => 0,
      "face" => 0,
      "hand" => 0,
      "body" => 0,
      "frame" => 0,
      "turntable" => 0,
      "explosion" => 0,
      "bgm" => 0,
      "folder_mask" => 0,
      "sudden" => 0,
      "judge_pos" => 0,
      "categoryvoice" => 0,
      "note" => 0,
      "fullcombo" => 0,
      "keybeam" => 0,
      "judgestring" => 0,
      "soundpreview" => 0,
      "grapharea" => 0,
      "effector_lock" => 0,
      "effector_type" => 0,
      "explosion_size" => 0,
      "alternate_hcn" => 0,
      "kokokara_start" => 0,
      "d_auto_adjust" => 0,
      "d_auto_scrach" => 0,
      "d_camera_layout" => 0,
      "d_disp_judge" => 0,
      "d_exscore" => 0,
      "d_gauge_disp" => 0,
      "d_ghost_score" => 0,
      "d_gno" => 0,
      "d_graph_score" => 0,
      "d_gtype" => 0,
      "d_hispeed" => 0.0,
      "d_judge" => 0,
      "d_judgeAdj" => 0,
      "d_lane_brignt" => 0,
      "d_liflen" => 0,
      "d_notes" => 0.0,
      "d_opstyle" => 0,
      "d_pace" => 0,
      "d_sdlen" => 0,
      "d_sdtype" => 0,
      "d_sorttype" => 0,
      "d_sub_gno" => 0,
      "d_timing" => 0,
      "d_timing_split" => 0,
      "d_tsujigiri_disp" => 0,
      "d_tune" => 0,
      "d_visualization" => 0,
      "dach" => 0,
      "dp_opt" => 0,
      "dp_opt2" => 0,
      "dpnum" => 0,
      "gpos" => 0,
      "mode" => 0,
      "ngrade" => 0,
      "pmode" => 0,
      "rtype" => 0,
      "s_auto_adjust" => 0,
      "s_auto_scrach" => 0,
      "s_camera_layout" => 0,
      "s_disp_judge" => 0,
      "s_exscore" => 0,
      "s_gauge_disp" => 0,
      "s_ghost_score" => 0,
      "s_gno" => 0,
      "s_graph_score" => 0,
      "s_gtype" => 0,
      "s_hispeed" => 0.0,
      "s_judge" => 0,
      "s_judgeAdj" => 0,
      "s_lane_brignt" => 0,
      "s_liflen" => 0,
      "s_notes" => 0.0,
      "s_opstyle" => 0,
      "s_pace" => 0,
      "s_sdlen" => 0,
      "s_sdtype" => 0,
      "s_sorttype" => 0,
      "s_sub_gno" => 0,
      "s_timing" => 0,
      "s_timing_split" => 0,
      "s_tsujigiri_disp" => 0,
      "s_tune" => 0,
      "s_visualization" => 0,
      "sach" => 0,
      "sp_opt" => 0,
      "spnum" => 0,
      "deller" => 0,
      # Step up mode
      "stepup_dp_fluctuation" => 0,
      "stepup_dp_level" => 0,
      "stepup_dp_mplay" => 0,
      "stepup_enemy_damage" => 0,
      "stepup_enemy_defeat_flg" => 0,
      "stepup_mission_clear_num" => 0,
      "stepup_progress" => 0,
      "stepup_sp_fluctuation" => 0,
      "stepup_sp_level" => 0,
      "stepup_sp_mplay" => 0,
      "stepup_tips_read_list" => 0,
      "stepup_total_point" => 0,
      "stepup_is_track_ticket" => 0,
      # DJ Rank
      "dj_rank_single_rank" => List.duplicate(0, 15),
      "dj_rank_double_rank" => List.duplicate(0, 15),
      "dj_rank_single_point" => List.duplicate(0, 15),
      "dj_rank_double_point" => List.duplicate(0, 15),
      # Notes Radar
      "notes_radar_single" => List.duplicate(0, 6),
      "notes_radar_double" => List.duplicate(0, 6),
      # Grades
      "grade_single" => -1,
      "grade_double" => -1,
      "grade_values" => [],
      # Achievements
      "achievements_trophy" => List.duplicate(0, 160),
      "achievements_last_weekly" => 0,
      "achievements_pack_comp" => 0,
      "achievements_pack_flg" => 0,
      "achievements_pack_id" => 0,
      "achievements_play_pack" => 0,
      "achievements_visit_flg" => 0,
      "achievements_weekly_num" => 0,
      # Other
      "language_setting" => 0,
      "movie_agreement" => 0,
      "lightning_play_data_spnum" => 0,
      "lightning_play_data_dpnum" => 0,
      # Lightning model settings
      "lightning_setting_slider" => List.duplicate(0, 7),
      "lightning_setting_light" => List.duplicate(1, 10),
      "lightning_setting_concentration" => 0,
      "lightning_setting_headphone_vol" => 0,
      "lightning_setting_resistance_sp_left" => 0,
      "lightning_setting_resistance_sp_right" => 0,
      "lightning_setting_resistance_dp_left" => 0,
      "lightning_setting_resistance_dp_right" => 0,
      "lightning_setting_skin_0" => 0,
      "lightning_setting_flg_skin_0" => 0,
      # Web UI/Other options
      "_show_category_grade" => 0,
      "_show_category_status" => 1,
      "_show_category_difficulty" => 1,
      "_show_category_alphabet" => 1,
      "_show_category_rival_play" => 0,
      "_show_category_rival_winlose" => 1,
      "_show_category_all_rival_play" => 0,
      "_show_category_arena_winlose" => 1,
      "_show_rival_shop_info" => 1,
      "_hide_play_count" => 0,
      "_show_score_graph_cutin" => 1,
      "_hide_iidx_id" => 0,
      "_classic_hispeed" => 0,
      "_beginner_option_swap" => 1,
      "_show_lamps_as_no_play_in_arena" => 0,
      "skin_customize_flag_frame" => 0,
      "skin_customize_flag_bgm" => 0,
      "skin_customize_flag_lane" => 0,
      # Rivals
      "sp_rival_1_iidx_id" => 0,
      "sp_rival_2_iidx_id" => 0,
      "sp_rival_3_iidx_id" => 0,
      "sp_rival_4_iidx_id" => 0,
      "sp_rival_5_iidx_id" => 0,
      "sp_rival_6_iidx_id" => 0,
      "dp_rival_1_iidx_id" => 0,
      "dp_rival_2_iidx_id" => 0,
      "dp_rival_3_iidx_id" => 0,
      "dp_rival_4_iidx_id" => 0,
      "dp_rival_5_iidx_id" => 0,
      "dp_rival_6_iidx_id" => 0
    }

    all_profiles_for_card =
      put_in(all_profiles_for_card, ["version", to_string(game_version)], version_profile)

    DB.upsert("iidx_profile", all_profiles_for_card, %{"card" => cid})

    {card, card_split} = get_id_from_profile(cid)

    response = E.e("response", E.e("IIDX30pc", id: card, id_str: card_split))

    Core.send_response(conn, info, response)
  end

  def iidx30pc_getlanegachaticket(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e("response",
        E.e(
          "IIDX30pc",
          for(i <- 0..5039,
            do:
              E.e("ticket",
                ticket_id: i,
                arrange_id: i,
                expire_date: 0
              )
          ) ++
            [
              E.e("setting",
                sp: -1,
                dp_left: -1,
                dp_right: -1
              ),
              E.e("info",
                last_page: 1
              ),
              E.e("free",
                num: 10
              ),
              E.e("favorite",
                arrange: 1_234_567
              )
            ]
        )
      )

    Core.send_response(conn, info, response)
  end

  def iidx30pc_consumelanegachaticket(conn) do
    {info, conn} = Core.process_request(conn)

    response = E.e("response", E.e("IIDX30pc"))

    Core.send_response(conn, info, response)
  end

  def iidx30pc_drawlanegacha(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e("response",
        E.e(
          "IIDX30pc",
          [
            E.e("ticket",
              ticket_id: 1,
              arrange_id: 1,
              expire_date: 0
            ),
            E.e("session", session_id: 1)
          ],
          status: 0
        )
      )

    Core.send_response(conn, info, response)
  end

  def iidx30pc_eaappliresult(conn) do
    {info, conn} = Core.process_request(conn)

    response = E.e("response", E.e("IIDX30pc"))

    Core.send_response(conn, info, response)
  end

  def iidx30pc_playstart(conn) do
    {info, conn} = Core.process_request(conn)

    response = E.e("response", E.e("IIDX30pc"))

    Core.send_response(conn, info, response)
  end

  def iidx30pc_playend(conn) do
    {info, conn} = Core.process_request(conn)

    response = E.e("response", E.e("IIDX30pc"))

    Core.send_response(conn, info, response)
  end

  def iidx30pc_delete(conn) do
    {info, conn} = Core.process_request(conn)

    response = E.e("response", E.e("IIDX30pc"))

    Core.send_response(conn, info, response)
  end

  def iidx30pc_logout(conn) do
    {info, conn} = Core.process_request(conn)

    response = E.e("response", E.e("IIDX30pc"))

    Core.send_response(conn, info, response)
  end
end
