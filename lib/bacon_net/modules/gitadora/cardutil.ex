defmodule BaconNet.Modules.Gitadora.Cardutil do
  @moduledoc "Port of modules/gitadora/cardutil.py."

  alias BaconNet.{Core, DB, E, XNode}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"{ver}_cardutil", "check", :gitadora_cardutil_check},
        {"{ver}_cardutil", "regist", :gitadora_cardutil_regist}
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

  def gitadora_cardutil_check(conn, ver) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    data = Core.module_node(info) |> XNode.child("player")

    _ = XNode.attr_int(data, "no")

    dataid = data |> XNode.child("refid") |> Map.get(:text)

    profile = get_game_profile(dataid, game_version)

    {state, name, did} =
      if profile == nil do
        {0, "", 0}
      else
        {2, profile["name"], 1}
      end

    response =
      E.e(
        "response",
        E.e(
          "#{ver}_cardutil",
          E.e(
            "player",
            [
              E.e("name", name, __type: "str"),
              E.e("charaid", 0, __type: "s32"),
              E.e("did", did, __type: "s32"),
              E.e("skilldata", [
                E.e("skill", 0, __type: "s32"),
                E.e("all_skill", 0, __type: "s32"),
                E.e("old_skill", 0, __type: "s32"),
                E.e("old_all_skill", 0, __type: "s32")
              ])
            ],
            no: 1,
            state: state
          )
        )
      )

    Core.send_response(conn, info, response)
  end

  def gitadora_cardutil_regist(conn, ver) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version
    _ = info.spec

    data = Core.module_node(info) |> XNode.child("player")

    no = XNode.attr_int(data, "no")

    dataid = data |> XNode.child("refid") |> Map.get(:text)

    all_profiles_for_card = DB.get("gitadora_profile", %{"card" => dataid})

    all_profiles_for_card =
      if not Map.has_key?(all_profiles_for_card, "gitadora_id") do
        gitadora_id = 10_000_000 + :rand.uniform(90_000_000) - 1
        Map.put(all_profiles_for_card, "gitadora_id", gitadora_id)
      else
        all_profiles_for_card
      end

    game_profile = %{
      "game_version" => game_version,
      "name" => "kors k",
      "title" => "MONKEY BUSINESS",
      "charaid" => 0,
      "stickers" => %{},
      "rival_card_ids" => []
    }

    game_data = %{
      "customdata_playstyle" => [
        0,
        1,
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
        0,
        0,
        0,
        0,
        20,
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
        0,
        20,
        0
      ],
      "customdata_custom" => List.duplicate(0, 50),
      "playinfo_cabid" => 1,
      "playinfo_play" => 0,
      "playinfo_playtime" => 0,
      "playinfo_playterm" => 0,
      "playinfo_session_cnt" => 0,
      "playinfo_saved_cnt" => 0,
      "playinfo_matching_num" => 0,
      "playinfo_extra_stage" => 0,
      "playinfo_extra_play" => 0,
      "playinfo_extra_clear" => 0,
      "playinfo_encore_play" => 0,
      "playinfo_encore_clear" => 0,
      "playinfo_pencore_play" => 0,
      "playinfo_pencore_clear" => 0,
      "playinfo_max_clear_diff" => 0,
      "playinfo_max_full_diff" => 0,
      "playinfo_max_exce_diff" => 0,
      "playinfo_clear_num" => 0,
      "playinfo_full_num" => 0,
      "playinfo_exce_num" => 0,
      "playinfo_no_num" => 0,
      "playinfo_e_num" => 0,
      "playinfo_d_num" => 0,
      "playinfo_c_num" => 0,
      "playinfo_b_num" => 0,
      "playinfo_a_num" => 0,
      "playinfo_s_num" => 0,
      "playinfo_ss_num" => 0,
      "playinfo_last_category" => 0,
      "playinfo_last_musicid" => 0,
      "playinfo_last_seq" => 0,
      "playinfo_disp_level" => 0,
      "tutorial_progress" => 0,
      "tutorial_disp_state" => 0,
      "information" => List.duplicate(0, 50),
      "reward" => List.duplicate(0, 50),
      "skilldata_skill" => 0,
      "skilldata_allskill" => 0,
      "groove_extra_gauge" => 0,
      "groove_encore_gauge" => 0,
      "groove_encore_cnt" => 0,
      "groove_encore_success" => 0,
      "groove_unlock_point" => 0,
      "record_max_skill" => 0,
      "record_max_all_skill" => 0,
      "record_max_clear_diff" => 0,
      "record_max_full_diff" => 0,
      "record_max_exce_diff" => 0,
      "record_max_clear_music_num" => 0,
      "record_max_full_music_num" => 0,
      "record_max_exce_music_num" => 0,
      "record_max_clear_seq_num" => 0,
      "record_max_classic_all_skill" => 0,
      "record_diff_100_nr" => 0,
      "record_diff_150_nr" => 0,
      "record_diff_200_nr" => 0,
      "record_diff_250_nr" => 0,
      "record_diff_300_nr" => 0,
      "record_diff_350_nr" => 0,
      "record_diff_400_nr" => 0,
      "record_diff_450_nr" => 0,
      "record_diff_500_nr" => 0,
      "record_diff_550_nr" => 0,
      "record_diff_600_nr" => 0,
      "record_diff_650_nr" => 0,
      "record_diff_700_nr" => 0,
      "record_diff_750_nr" => 0,
      "record_diff_800_nr" => 0,
      "record_diff_850_nr" => 0,
      "record_diff_900_nr" => 0,
      "record_diff_950_nr" => 0,
      "record_diff_100_clear" => List.duplicate(0, 7),
      "record_diff_150_clear" => List.duplicate(0, 7),
      "record_diff_200_clear" => List.duplicate(0, 7),
      "record_diff_250_clear" => List.duplicate(0, 7),
      "record_diff_300_clear" => List.duplicate(0, 7),
      "record_diff_350_clear" => List.duplicate(0, 7),
      "record_diff_400_clear" => List.duplicate(0, 7),
      "record_diff_450_clear" => List.duplicate(0, 7),
      "record_diff_500_clear" => List.duplicate(0, 7),
      "record_diff_550_clear" => List.duplicate(0, 7),
      "record_diff_600_clear" => List.duplicate(0, 7),
      "record_diff_650_clear" => List.duplicate(0, 7),
      "record_diff_700_clear" => List.duplicate(0, 7),
      "record_diff_750_clear" => List.duplicate(0, 7),
      "record_diff_800_clear" => List.duplicate(0, 7),
      "record_diff_850_clear" => List.duplicate(0, 7),
      "record_diff_900_clear" => List.duplicate(0, 7),
      "record_diff_950_clear" => List.duplicate(0, 7),
      "favorite_music_list_1" => List.duplicate(-1, 100),
      "favorite_music_list_2" => List.duplicate(-1, 100),
      "favorite_music_list_3" => List.duplicate(-1, 100),
      "recommend_musicid_list" => List.duplicate(-1, 5),
      "thanks_medal_medal" => 0,
      "thanks_medal_granted_total_medal" => 0
      # "skindata_skin" => List.duplicate(0, 100),
    }

    game_profile =
      game_profile
      |> Map.put("drummania", game_data)
      |> Map.put("guitarfreaks", game_data)

    version_key = to_string(game_version)

    all_profiles_for_card =
      Map.put(
        all_profiles_for_card,
        "version",
        Map.put(Map.get(all_profiles_for_card, "version", %{}), version_key, game_profile)
      )

    DB.upsert("gitadora_profile", all_profiles_for_card, %{"card" => dataid})

    response =
      E.e(
        "response",
        E.e(
          "#{ver}_cardutil",
          E.e(
            "player",
            [
              E.e("is_succession", 0, __type: "bool"),
              E.e("did", 1, __type: "s32")
            ],
            no: no
          )
        )
      )

    Core.send_response(conn, info, response)
  end
end
