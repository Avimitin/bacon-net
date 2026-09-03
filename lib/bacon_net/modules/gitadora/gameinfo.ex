defmodule BaconNet.Modules.Gitadora.Gameinfo do
  @moduledoc false

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"{ver}_gameinfo", "get", :gitadora_gameinfo_get}
      ]
    }
  end

  def gitadora_gameinfo_get(conn, ver) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    lv_type = if game_version >= 10, do: "s32", else: "u8"
    limit_type = if game_version >= 9, do: "s32", else: "u8"

    general_terms = [
      "paseli_lottery_info_2020",
      "50th_konami_logo",
      "mix_up_2022_info",
      "guitar_controller_reward_2021",
      "bpl_season3_info_2023",
      "knst_musicpack_17",
      "knst_sp_music_202203",
      "kac_11th_A_info",
      "kac_11th_B_info",
      "paseli_festival_info_2023_11",
      "bpl_season3_info_sdvx",
      "otobear_birthday",
      "custom_skip_dm",
      "ticket_contents_ver",
      "ultimate_mobile_2019_info",
      "cardconnect_champ",
      "kac_9th_info",
      "floor_break_info"
    ]

    response =
      E.e(
        "response",
        E.e(
          "#{ver}_gameinfo",
          [
            E.e("now_date", round(:os.system_time(:millisecond) / 1000), __type: "u64"),
            E.e("extra", [
              E.e("extra_lv", 0, __type: lv_type),
              E.e(
                "extramusic",
                E.e("music", [
                  E.e("musicid", 0, __type: "s32"),
                  E.e("get_border", 0, __type: "u8")
                ])
              )
            ]),
            E.e(
              "general_term",
              Enum.map(general_terms, fn s ->
                E.e("termdata", [
                  E.e("type", "general_#{s}", __type: "str"),
                  E.e("term", 1, __type: lv_type),
                  E.e("state", 0, __type: "s32"),
                  E.e("start_date_ms", 0, __type: "u64"),
                  E.e("end_date_ms", 0, __type: "u64")
                ])
              end)
            ),
            E.e("phrase_combo_challenge", [
              E.e("term", 1, __type: "u8"),
              E.e("start_date_ms", 0, __type: "u64"),
              E.e("end_date_ms", 0, __type: "u64")
            ]),
            E.e("sdvx_stamprally3", [
              E.e("term", 1, __type: "u8"),
              E.e("start_date_ms", 0, __type: "u64"),
              E.e("end_date_ms", 0, __type: "u64")
            ]),
            E.e("chronicle_1", [
              E.e("term", 1, __type: "u8"),
              E.e("start_date_ms", 0, __type: "u64"),
              E.e("end_date_ms", 0, __type: "u64")
            ]),
            E.e("paseli_point_lottery", [
              E.e("term", 1, __type: "u8"),
              E.e("start_date_ms", 0, __type: "u64"),
              E.e("end_date_ms", 0, __type: "u64")
            ])
          ] ++
            Enum.map(2..20, fn x ->
              E.e("phrase_combo_challenge_#{x}", [
                E.e("term", 1, __type: "u8"),
                E.e("start_date_ms", 0, __type: "u64"),
                E.e("end_date_ms", 0, __type: "u64")
              ])
            end) ++
            [
              E.e("long_otobear_fes_1", [
                E.e("term", 1, __type: "u8"),
                E.e("start_date_ms", 0, __type: "u64"),
                E.e("end_date_ms", 0, __type: "u64"),
                E.e("bonus_musicid")
              ]),
              E.e(
                "monstar_subjugation",
                [
                  E.e("bonus_musicid", 0, __type: "s32")
                ] ++
                  Enum.map(1..4, fn x ->
                    E.e("monstar_subjugation_#{x}", [
                      E.e("term", 1, __type: "u8"),
                      E.e("start_date_ms", 0, __type: "u64"),
                      E.e("end_date_ms", 0, __type: "u64")
                    ])
                  end)
              ),
              E.e(
                "bear_fes",
                Enum.map(1..4, fn x ->
                  E.e("bear_fes_#{x}", [
                    E.e("term", 1, __type: "u8"),
                    E.e("start_date_ms", 0, __type: "u64"),
                    E.e("end_date_ms", 0, __type: "u64")
                  ])
                end)
              )
            ] ++
            Enum.map(1..3, fn x ->
              E.e("kouyou_challenge_#{x}", [
                E.e("term", 0, __type: "u8"),
                E.e("bonus_musicid", 0, __type: "s32")
              ])
            end) ++
            Enum.map(["thanksgiving", "lotterybox"], fn x ->
              E.e(x, [
                E.e("term", 1, __type: "u8"),
                E.e("start_date_ms", 0, __type: "u64"),
                E.e("end_date_ms", 0, __type: "u64"),
                E.e(
                  "box_term",
                  E.e("state", 0, __type: "u8")
                )
              ])
            end) ++
            [
              E.e("sticker_campaign", [
                E.e("term", 0, __type: "u8"),
                E.e("sticker_list")
              ]),
              E.e(
                "infect_music",
                E.e("term", 1, __type: "u8")
              ),
              E.e(
                "unlock_challenge",
                E.e("term", 0, __type: lv_type)
              ),
              E.e(
                "battle",
                E.e("term", 1, __type: lv_type)
              ),
              E.e(
                "battle_chara",
                E.e("term", 1, __type: lv_type)
              ),
              E.e(
                "data_ver_limit",
                E.e("term", 0, __type: limit_type)
              ),
              E.e(
                "ea_pass_propel",
                E.e("term", 0, __type: lv_type)
              ),
              E.e("monthly_skill", [
                E.e("term", 0, __type: "u8"),
                E.e(
                  "target_music",
                  E.e(
                    "music",
                    E.e("musicid", 0, __type: "s32")
                  )
                )
              ]),
              E.e(
                "update_prog",
                E.e("term", 0, __type: lv_type)
              ),
              E.e("rockwave", E.e("event_list")),
              E.e("livehouse", [
                E.e("event_list"),
                E.e("bonus", [
                  E.e("term", 0, __type: "u8"),
                  E.e("stage_bonus", 0, __type: "s32"),
                  E.e("charm_bonus", 0, __type: "s32"),
                  E.e("start_date_ms", 0, __type: "u64"),
                  E.e("end_date_ms", 0, __type: "u64")
                ])
              ]),
              E.e("general_term"),
              E.e("jubeat_omiyage_challenge"),
              E.e("kac2017"),
              E.e("nostalgia_concert"),
              E.e("trbitemdata"),
              E.e("ctrl_movie"),
              E.e("ng_jacket"),
              E.e("ng_recommend_music"),
              E.e("ranking", [
                E.e("skill_0_999"),
                E.e("skill_1000_1499"),
                E.e("skill_1500_1999"),
                E.e("skill_2000_2499"),
                E.e("skill_2500_2999"),
                E.e("skill_3000_3499"),
                E.e("skill_3500_3999"),
                E.e("skill_4000_4499"),
                E.e("skill_4500_4999"),
                E.e("skill_5000_5499"),
                E.e("skill_5500_5999"),
                E.e("skill_6000_6499"),
                E.e("skill_6500_6999"),
                E.e("skill_7000_7499"),
                E.e("skill_7500_7999"),
                E.e("skill_8000_8499"),
                E.e("skill_8500_9999"),
                E.e("total"),
                E.e("original"),
                E.e("bemani"),
                E.e("famous"),
                E.e("anime"),
                E.e("band"),
                E.e("western")
              ]),
              E.e("processing_report_state", 0, __type: "u8"),
              E.e("assert_report_state", 0, __type: "u8"),
              E.e(
                "recommendmusic",
                E.e(
                  "music",
                  E.e("musicid", 0, __type: "s32")
                ),
                nr: 1
              ),
              E.e("demomusic", nr: 0),
              E.e("event_skill"),
              E.e(
                "temperature",
                E.e("is_send", 0, __type: "bool")
              ),
              E.e(
                "bemani_summer_2018",
                E.e("is_open", 0, __type: "bool")
              ),
              E.e(
                "kac2018",
                E.e("event", [
                  E.e("term", 0, __type: "s32"),
                  E.e("since", 0, __type: "u64"),
                  E.e("till", 0, __type: "u64"),
                  E.e("is_open", 0, __type: "bool"),
                  E.e(
                    "target_music",
                    E.e("music_id", List.duplicate(0, 6), __type: "s32")
                  )
                ])
              )
            ]
        )
      )

    Core.send_response(conn, info, response)
  end
end
