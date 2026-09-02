defmodule BaconNet.Modules.Iidx.Pc do
  @moduledoc "Port of modules/iidx/pc.py."

  import Bitwise

  alias BaconNet.{Config, Core, DB, E, XNode}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"pc", "get", :pc_get},
        {"pc", "common", :pc_common},
        {"pc", "save", :pc_save},
        {"pc", "visit", :pc_visit},
        {"pc", "reg", :pc_reg},
        {"pc", "logout", :pc_logout}
      ]
    }
  end

  defp get_profile(cid), do: DB.get("iidx_profile", %{"card" => cid})

  defp get_profile_by_id(iidx_id), do: DB.get("iidx_profile", %{"iidx_id" => iidx_id})

  defp get_game_profile(cid, game_version) do
    profile = get_profile(cid)

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
      Map.get(profile, "_hide_rival_info", 0) <<< 9
  end

  def pc_get(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    node = Core.module_node(info)
    cid = XNode.attr(node, "rid")
    profile = get_game_profile(cid, game_version)
    {djid, djid_split} = get_id_from_profile(cid)

    response =
      cond do
        game_version == 20 ->
          E.e(
            "response",
            E.e("pc", [
              E.e("pcdata",
                dach: profile["dach"],
                dp_opt: profile["dp_opt"],
                dp_opt2: profile["dp_opt2"],
                dpnum: profile["dpnum"],
                gno: profile["gno"],
                gpos: profile["gpos"],
                help: profile["help"],
                hispeed: profile["hispeed"],
                id: djid,
                idstr: djid_split,
                judge: profile["judge"],
                judgeAdj: profile["judgeAdj"],
                liflen: profile["lift"],
                mode: profile["mode"],
                name: profile["djname"],
                notes: profile["notes"],
                opstyle: profile["opstyle"],
                pase: profile["pase"],
                pid: profile["region"],
                pmode: profile["pmode"],
                sach: profile["sach"],
                sdhd: profile["sdhd"],
                sdtype: profile["sdtype"],
                sp_opt: profile["sp_opt"],
                spnum: profile["spnum"],
                timing: profile["timing"]
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
                  0,
                  profile["turntable"],
                  profile["explosion"],
                  profile["bgm"],
                  calculate_folder_mask(profile),
                  profile["sudden"],
                  0,
                  profile["categoryvoice"],
                  profile["note"],
                  profile["fullcombo"],
                  profile["keybeam"],
                  profile["judgestring"],
                  -1,
                  profile["soundpreview"]
                ],
                __type: "s16"
              ),
              E.e("rlist"),
              E.e("commonboss", baron: 0, deller: profile["deller"], orb: 0),
              E.e("secret", [
                E.e("flg1", Map.get(profile, "secret_flg1", [-1]), __type: "s64"),
                E.e("flg2", Map.get(profile, "secret_flg2", [-1]), __type: "s64"),
                E.e("flg3", Map.get(profile, "secret_flg3", [-1]), __type: "s64")
              ]),
              E.e("join_shop",
                join_cflg: 1,
                join_id: 10,
                join_name: Config.arcade(),
                joinflg: 1
              ),
              E.e(
                "grade",
                Enum.map(profile["grade_values"], fn x -> E.e("g", x, __type: "u8") end),
                dgid: profile["grade_double"],
                sgid: profile["grade_single"]
              ),
              E.e("redboss",
                crush: Map.get(profile, "redboss_crush", 0),
                open: Map.get(profile, "redboss_open", 0),
                progress: Map.get(profile, "redboss_progress", 0)
              ),
              E.e("blueboss",
                column0: Map.get(profile, "blueboss_column0", 0),
                column1: Map.get(profile, "blueboss_column1", 0),
                first_flg: Map.get(profile, "blueboss_first_flg", 0),
                gauge: Map.get(profile, "blueboss_gauge", 0),
                general: Map.get(profile, "blueboss_general", 0),
                item: Map.get(profile, "blueboss_item", 0),
                item_flg: Map.get(profile, "blueboss_item_flg", 0),
                level: Map.get(profile, "blueboss_level", 0),
                row0: Map.get(profile, "blueboss_row0", 0),
                row1: Map.get(profile, "blueboss_row1", 0),
                sector: Map.get(profile, "blueboss_sector", 0)
              ),
              E.e(
                "yellowboss",
                [
                  E.e("p_attack", Map.get(profile, "yellowboss_p_attack", List.duplicate(0, 7)),
                    __type: "s32"
                  ),
                  E.e(
                    "pbest_attack",
                    Map.get(profile, "yellowboss_pbest_attack", List.duplicate(0, 7)),
                    __type: "s32"
                  ),
                  E.e("defeat", Map.get(profile, "yellowboss_defeat", List.duplicate(0, 7)),
                    __type: "bool"
                  ),
                  E.e(
                    "shop_damage",
                    Map.get(profile, "yellowboss_shop_damage", List.duplicate(0, 7)),
                    __type: "s32"
                  )
                ],
                critical: Map.get(profile, "yellowboss_critical", 0),
                destiny: Map.get(profile, "yellowboss_destiny", 0),
                first_flg: Map.get(profile, "yellowboss_first_flg", 1),
                heroic0: Map.get(profile, "yellowboss_heroic0", 0),
                heroic1: Map.get(profile, "yellowboss_heroic1", 0),
                join_num: Map.get(profile, "yellowboss_join_num", 0),
                last_select: Map.get(profile, "yellowboss_last_select", 0),
                level: Map.get(profile, "yellowboss_level", 1),
                shop_message: Map.get(profile, "yellowboss_shop_message", ""),
                special_move: Map.get(profile, "yellowboss_special_move", "")
              ),
              E.e("link5",
                anisakis: 1,
                bad: 1,
                beachside: 1,
                beautiful: 1,
                broken: 1,
                castle: 1,
                china: 1,
                cuvelia: 1,
                exusia: 1,
                fallen: 1,
                flip: 1,
                glass: 1,
                glassflg: 1,
                qpro: 1,
                qproflg: 1,
                quaver: 1,
                reflec_data: 1,
                reunion: 1,
                sakura: 1,
                sampling: 1,
                second: 1,
                summer: 1,
                survival: 1,
                thunder: 1,
                titans: 1,
                treasure: 1,
                turii: 1,
                waxing: 1,
                whydidyou: 1,
                wuv: 1
              ),
              E.e("cafe",
                astraia: 1,
                bastie: 1,
                beachimp: 1,
                food: 0,
                holysnow: 1,
                is_first: 0,
                ledvsscu: 1,
                pastry: 0,
                rainbow: 1,
                service: 0,
                trueblue: 1
              ),
              E.e("tricolettepark",
                attack_rate: 0,
                boss0_damage: 0,
                boss0_stun: 0,
                boss1_damage: 0,
                boss1_stun: 0,
                boss2_damage: 0,
                boss2_stun: 0,
                boss3_damage: 0,
                boss3_stun: 0,
                is_union: 0,
                magic_gauge: 0,
                open_music: -1,
                party: 0
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
              E.e("visitor", anum: 1, pnum: 2, snum: 1, vs_flg: 1),
              E.e("gakuen", music_list: -1),
              E.e(
                "achievements",
                E.e("trophy", Map.get(profile, "achievements_trophy", []) |> Enum.take(10),
                  __type: "s64"
                ),
                last_weekly: Map.get(profile, "achievements_last_weekly", 0),
                pack: Map.get(profile, "achievements_pack_id", 0),
                pack_comp: Map.get(profile, "achievements_pack_comp", 0),
                rival_crush: 0,
                visit_flg: Map.get(profile, "achievements_visit_flg", 0),
                weekly_num: Map.get(profile, "achievements_weekly_num", 0)
              ),
              E.e(
                "step",
                [
                  E.e("stamp", Map.get(profile, "stepup_stamp", ""), __type: "bin"),
                  E.e("help", Map.get(profile, "stepup_help", ""), __type: "bin")
                ],
                dp_ach: Map.get(profile, "stepup_dp_ach", 0),
                dp_hdpt: Map.get(profile, "stepup_dp_hdpt", 0),
                dp_level: Map.get(profile, "stepup_dp_level", 0),
                dp_mplay: Map.get(profile, "stepup_dp_mplay", 0),
                dp_round: Map.get(profile, "stepup_dp_round", 0),
                review: Map.get(profile, "stepup_review", 0),
                sp_ach: Map.get(profile, "stepup_sp_ach", 0),
                sp_hdpt: Map.get(profile, "stepup_sp_hdpt", 0),
                sp_level: Map.get(profile, "stepup_sp_level", 0),
                sp_mplay: Map.get(profile, "stepup_sp_mplay", 0),
                sp_round: Map.get(profile, "stepup_sp_round", 0)
              )
            ])
          )

        game_version == 19 ->
          E.e(
            "response",
            E.e("pc", [
              E.e("pcdata",
                dach: profile["dach"],
                dp_opt: profile["dp_opt"],
                dp_opt2: profile["dp_opt2"],
                dpnum: profile["dpnum"],
                gno: profile["gno"],
                help: profile["help"],
                id: djid,
                idstr: djid_split,
                liflen: profile["lift"],
                mode: profile["mode"],
                name: profile["djname"],
                notes: profile["notes"],
                pase: profile["pase"],
                pid: profile["region"],
                pmode: profile["pmode"],
                sach: profile["sach"],
                sdhd: profile["sdhd"],
                sdtype: profile["sdtype"],
                sflg0: -1,
                sflg1: -1,
                sp_opt: profile["sp_opt"],
                spnum: profile["spnum"],
                timing: profile["timing"]
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
                  0,
                  profile["categoryvoice"],
                  profile["note"],
                  profile["fullcombo"],
                  profile["keybeam"],
                  profile["judgestring"],
                  0,
                  0
                ],
                __type: "s16"
              ),
              E.e("grade",
                dgid: profile["grade_double"],
                sgid: profile["grade_single"]
              ),
              E.e("ex"),
              E.e("ocrs"),
              E.e(
                "step",
                [
                  E.e("sp_cflg", "", __type: "bin"),
                  E.e("dp_cflg", "", __type: "bin")
                ],
                dp_ach: 0,
                dp_dif: 0,
                sp_ach: 0,
                sp_dif: 0
              ),
              E.e("lincle", comflg: 1),
              E.e("reflec", br: 1, sg: 1, sr: 1, ssc: 1, tb: 1, tf: 1, wu: 1),
              E.e("phase2", wonder: 1, yellow: 1),
              E.e("event", knee: 1, lethe: 0, resist: 0, jknee: 1, jlethe: 0, jresist: 0),
              E.e("phase4",
                qpro: 1,
                glass: 1,
                treasure: 1,
                beautiful: 1,
                quaver: 1,
                castle: 1,
                flip: 1,
                titans: 1,
                exusia: 1,
                waxing: 1,
                sampling: 1,
                beachside: 1,
                cuvelia: 1,
                qproflg: 1,
                glassflg: 1,
                reunion: 1,
                bad: 1,
                turii: 1,
                anisakis: 1,
                second: 1,
                whydidyou: 1,
                china: 1,
                fallen: 1,
                broken: 1,
                summer: 1,
                sakura: 1,
                wuv: 1,
                survival: 1,
                thunder: 1
              ),
              E.e(
                "shop",
                E.e("item", [3, 3, 3], __type: "u8"),
                spitem: 1
              ),
              E.e("rlist")
            ])
          )

        game_version == 18 ->
          E.e(
            "response",
            E.e("pc", [
              E.e("pcdata",
                dach: profile["dach"],
                dp_opt: profile["dp_opt"],
                dp_opt2: profile["dp_opt2"],
                dpnum: profile["dpnum"],
                gno: profile["gno"],
                id: djid,
                idstr: djid_split,
                liflen: profile["lift"],
                mcomb: 0,
                mode: profile["mode"],
                name: profile["djname"],
                ncomb: 0,
                pid: profile["region"],
                pmode: profile["pmode"],
                sach: profile["sach"],
                sdhd: profile["sdhd"],
                sdtype: profile["sdtype"],
                sflg0: -1,
                sflg1: -1,
                sp_opt: profile["sp_opt"],
                spnum: profile["spnum"],
                timing: profile["timing"]
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
                  0,
                  0,
                  0,
                  0,
                  0,
                  0
                ],
                __type: "u16"
              ),
              E.e("grade",
                dgid: "-1",
                sgid: "-1"
              ),
              E.e("ex"),
              E.e("ocrs"),
              E.e("rlist")
            ])
          )
      end

    Core.send_response(conn, info, response)
  end

  def pc_common(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    response =
      cond do
        game_version == 20 ->
          E.e(
            "response",
            E.e(
              "pc",
              [
                E.e(
                  "mranking",
                  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
                  __type: "u16"
                ),
                E.e("ir", beat: 2),
                E.e("boss", phase: 0),
                E.e("red", phase: 2),
                E.e("yellow", phase: 4),
                E.e("limit", phase: 25),
                E.e("cafe", open: 1),
                E.e(
                  "yellow_correct",
                  for(
                    _ <- 1..6,
                    do:
                      E.e("detail",
                        avg_shop: 7,
                        critical: 2,
                        max_condition: 18,
                        max_member: 20,
                        max_resist: 1,
                        min_condition: 10,
                        min_member: 1,
                        min_resist: 1,
                        rival: 2
                      )
                  ) ++
                    [
                      E.e("detail",
                        avg_shop: 7,
                        critical: 2,
                        max_condition: 144,
                        max_member: 20,
                        max_resist: 1,
                        min_condition: 80,
                        min_member: 1,
                        min_resist: 1,
                        rival: 2
                      )
                    ],
                  avg_shop: 7
                )
              ],
              expire: 600
            )
          )

        game_version == 19 ->
          E.e(
            "response",
            E.e(
              "pc",
              [
                E.e("secret", [
                  E.e("mid", [1901, 1914, 1946, 1955, 1956, 1966], __type: "u16"),
                  E.e("open", [1, 1, 1, 1, 1, 1], __type: "bool")
                ]),
                E.e("boss", phase: 2),
                E.e("ir", beat: 2),
                E.e("travel", flg: 1),
                E.e("lincle", phase: 4),
                E.e("monex", no: 3)
              ],
              expire: 600
            )
          )

        game_version == 18 ->
          E.e(
            "response",
            E.e(
              "pc",
              [
                E.e("cmd",
                  gmbl: 1,
                  gmbla: 1,
                  regl: 1,
                  rndp: 1,
                  hrnd: 1,
                  alls: 1
                ),
                E.e("lg", lea: 1),
                E.e("ir", beat: 3),
                E.e("ev", pha: 2)
              ],
              expire: 600
            )
          )
      end

    Core.send_response(conn, info, response)
  end

  def pc_save(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    root = Core.module_node(info)

    xid = XNode.attr(root, "iidxid") |> String.to_integer()
    clt = XNode.attr(root, "cltype") |> String.to_integer()

    profile = get_profile_by_id(xid)
    game_profile = get_in(profile, ["version", to_string(game_version)]) || %{}

    game_profile =
      cond do
        clt == 0 ->
          game_profile
          |> Map.put("sach", XNode.attr(root, "achi"))
          |> Map.put("sp_opt", XNode.attr(root, "opt"))

        clt == 1 ->
          game_profile
          |> Map.put("dach", XNode.attr(root, "achi"))
          |> Map.put("dp_opt", XNode.attr(root, "opt"))
          |> Map.put("dp_opt2", XNode.attr(root, "opt2"))

        true ->
          game_profile
      end

    game_profile =
      Enum.reduce(
        [
          "gno",
          "gpos",
          "help",
          "hispeed",
          "judge",
          "judgeAdj",
          "lift",
          "mode",
          "notes",
          "opstyle",
          "pnum",
          "sdhd",
          "sdtype",
          "timing"
        ],
        game_profile,
        fn k, gp ->
          case XNode.attr(root, k) do
            nil -> gp
            v -> Map.put(gp, k, v)
          end
        end
      )

    game_profile =
      case XNode.child(root, "secret") do
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
      case XNode.child(root, "step") do
        nil ->
          game_profile

        step ->
          gp =
            Enum.reduce(
              [
                "dp_level",
                "dp_mplay",
                "enemy_damage",
                "enemy_defeat_flg",
                "mission_clear_num",
                "progress",
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
            nil ->
              gp

            is_track_ticket ->
              Map.put(gp, "stepup_is_track_ticket", String.to_integer(is_track_ticket.text))
          end
      end

    game_profile =
      case XNode.child(root, "achievements") do
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
                Map.put(
                  acc,
                  "achievements_" <> k,
                  XNode.attr(achievements, k) |> String.to_integer()
                )
              end
            )

          case XNode.child(achievements, "trophy") do
            nil -> gp
            trophy -> Map.put(gp, "achievements_trophy", XNode.text_ints(trophy))
          end
      end

    profile =
      case XNode.child(root, "grade") do
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
      case XNode.child(root, "commonboss") do
        nil -> deller_amount
        commonboss -> XNode.attr(commonboss, "deller") |> String.to_integer()
      end

    game_profile = Map.put(game_profile, "deller", deller_amount)

    game_profile =
      game_profile
      |> Map.put("spnum", Map.get(game_profile, "spnum", 0) + if(clt == 0, do: 1, else: 0))
      |> Map.put("dpnum", Map.get(game_profile, "dpnum", 0) + if(clt == 1, do: 1, else: 0))

    profile = put_in(profile, ["version", to_string(game_version)], game_profile)

    DB.upsert("iidx_profile", profile, %{"iidx_id" => xid})

    response = E.e("response", E.e("pc", iidxid: xid, cltype: clt))

    Core.send_response(conn, info, response)
  end

  def pc_visit(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("pc",
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

  def pc_reg(conn) do
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

    version_profile =
      cond do
        game_version == 20 ->
          %{
            "game_version" => game_version,
            "djname" => name,
            "region" => String.to_integer(pid),
            "head" => 0,
            "hair" => 0,
            "face" => 0,
            "hand" => 0,
            "body" => 0,
            "turntable" => 0,
            "explosion" => 0,
            "bgm" => 0,
            "folder_mask" => 0,
            "sudden" => 0,
            "categoryvoice" => 0,
            "note" => 0,
            "fullcombo" => 0,
            "keybeam" => 0,
            "judgestring" => 0,
            "soundpreview" => 0,
            "dach" => 0,
            "dp_opt" => 0,
            "dp_opt2" => 0,
            "dpnum" => 0,
            "gno" => 0,
            "gpos" => 0,
            "help" => 0,
            "hispeed" => 0,
            "judge" => 0,
            "judgeAdj" => 0,
            "lift" => 0,
            "mode" => 0,
            "notes" => 0,
            "opstyle" => 0,
            "pase" => 0,
            "pmode" => 0,
            "sach" => 0,
            "sdhd" => 50,
            "sdtype" => 0,
            "sp_opt" => 0,
            "spnum" => 0,
            "timing" => 0,
            "deller" => 0,
            # Step up mode
            "stepup_stamp" => "",
            "stepup_help" => "",
            "stepup_dp_ach" => 0,
            "stepup_dp_hdpt" => 0,
            "stepup_dp_level" => 0,
            "stepup_dp_mplay" => 0,
            "stepup_dp_round" => 0,
            "stepup_review" => 0,
            "stepup_sp_ach" => 0,
            "stepup_sp_hdpt" => 0,
            "stepup_sp_level" => 0,
            "stepup_sp_mplay" => 0,
            "stepup_sp_round" => 0,
            # Grades
            "grade_single" => -1,
            "grade_double" => -1,
            "grade_values" => [],
            # Achievements
            "achievements_trophy" => List.duplicate(0, 80),
            "achievements_last_weekly" => 0,
            "achievements_pack_comp" => 0,
            "achievements_pack_flg" => 0,
            "achievements_pack_id" => 0,
            "achievements_play_pack" => 0,
            "achievements_visit_flg" => 0,
            "achievements_weekly_num" => 0,
            # Web UI/Other options
            "_show_category_grade" => 0,
            "_show_category_status" => 1,
            "_show_category_difficulty" => 1,
            "_show_category_alphabet" => 1,
            "_show_category_rival_play" => 0,
            "_show_category_rival_winlose" => 0,
            "_show_rival_shop_info" => 0,
            "_hide_play_count" => 0,
            "_hide_rival_info" => 1
          }

        game_version == 19 ->
          %{
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
            "categoryvoice" => 0,
            "note" => 0,
            "fullcombo" => 0,
            "keybeam" => 0,
            "judgestring" => 0,
            "dach" => 0,
            "dp_opt" => 0,
            "dp_opt2" => 0,
            "dpnum" => 0,
            "gno" => 0,
            "help" => 0,
            "lift" => 0,
            "mode" => 0,
            "notes" => 0,
            "pase" => 0,
            "pmode" => 0,
            "sach" => 0,
            "sdhd" => 50,
            "sdtype" => 0,
            "sp_opt" => 0,
            "spnum" => 0,
            "timing" => 0,
            # Grades
            "grade_single" => -1,
            "grade_double" => -1,
            "grade_values" => [],
            # Web UI/Other options
            "_show_category_grade" => 0,
            "_show_category_status" => 1,
            "_show_category_difficulty" => 1,
            "_show_category_alphabet" => 1,
            "_show_category_rival_play" => 0,
            "_show_category_rival_winlose" => 0,
            "_show_rival_shop_info" => 0,
            "_hide_play_count" => 0,
            "_hide_rival_info" => 1
          }

        game_version == 18 ->
          %{
            "game_version" => game_version,
            "djname" => name,
            "region" => String.to_integer(pid),
            "frame" => 0,
            "turntable" => 0,
            "explosion" => 0,
            "bgm" => 0,
            "folder_mask" => 0,
            "sudden" => 0,
            "dach" => 0,
            "dp_opt" => 0,
            "dp_opt2" => 0,
            "dpnum" => 0,
            "gno" => 0,
            "lift" => 0,
            "mode" => 0,
            "pmode" => 0,
            "sach" => 0,
            "sdhd" => 50,
            "sdtype" => 0,
            "sp_opt" => 0,
            "spnum" => 0,
            "timing" => 0,
            # Grades
            "grade_single" => -1,
            "grade_double" => -1,
            "grade_values" => [],
            # Web UI/Other options
            "_show_category_grade" => 0,
            "_show_category_status" => 1,
            "_show_category_difficulty" => 1,
            "_show_category_alphabet" => 1,
            "_show_category_rival_play" => 0,
            "_show_category_rival_winlose" => 0,
            "_show_rival_shop_info" => 0,
            "_hide_play_count" => 0,
            "_hide_rival_info" => 1
          }

        true ->
          nil
      end

    all_profiles_for_card =
      if version_profile != nil do
        put_in(all_profiles_for_card, ["version", to_string(game_version)], version_profile)
      else
        all_profiles_for_card
      end

    DB.upsert("iidx_profile", all_profiles_for_card, %{"card" => cid})

    {card, card_split} = get_id_from_profile(cid)

    response = E.e("response", E.e("pc", id: card, id_str: card_split))

    Core.send_response(conn, info, response)
  end

  def pc_logout(conn) do
    {info, conn} = Core.process_request(conn)

    response = E.e("response", E.e("pc"))

    Core.send_response(conn, info, response)
  end
end
