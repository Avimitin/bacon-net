defmodule BaconNet.Modules.Iidx.Iidx32gamesystem do
  @moduledoc "Port of modules/iidx/iidx32gamesystem.py."

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"IIDX32gameSystem", "systemInfo", :iidx32gamesystem_systeminfo}
      ]
    }
  end

  defp grade_course(play_style, grade_id, [music_id_0, music_id_1, music_id_2, music_id_3]) do
    E.e("grade_course", [
      E.e("play_style", play_style, __type: "s32"),
      E.e("grade_id", grade_id, __type: "s32"),
      E.e("music_id_0", music_id_0, __type: "s32"),
      E.e("class_id_0", 3, __type: "s32"),
      E.e("music_id_1", music_id_1, __type: "s32"),
      E.e("class_id_1", 3, __type: "s32"),
      E.e("music_id_2", music_id_2, __type: "s32"),
      E.e("class_id_2", 3, __type: "s32"),
      E.e("music_id_3", music_id_3, __type: "s32"),
      E.e("class_id_3", 3, __type: "s32"),
      E.e("is_valid", 1, __type: "bool")
    ])
  end

  def iidx32gamesystem_systeminfo(conn) do
    {info, conn} = Core.process_request(conn)

    unlock = []
    # force unlock LM exclusives to complete unlock all songs server side
    # this makes LM exclusive folder disappear, so just use hex edits
    # unlock = (30106, 31084, 30077, 31085, 30107, 30028, 30076, 31083, 30098)

    current_time = :os.system_time(:second)

    # E.option_2pp(),
    children =
      (for mid <- unlock do
         E.e("music_open", [
           E.e("music_id", mid, __type: "s32"),
           E.e("kind", 0, __type: "s32")
         ])
       end) ++
        [
          grade_course(0, 15, [19022, 23068, 27013, 29045]),
          grade_course(0, 16, [27034, 24023, 16009, 25085]),
          grade_course(0, 17, [26087, 19002, 29050, 30024]),
          grade_course(0, 18, [30052, 18032, 16020, 12004]),
          grade_course(1, 15, [12002, 31063, 23046, 30020]),
          grade_course(1, 16, [26106, 14021, 29052, 23075]),
          grade_course(1, 17, [29042, 26043, 17017, 28005]),
          grade_course(1, 18, [25007, 29017, 19002, 9028]),
          E.e("arena_schedule", [
            E.e("season", 1, __type: "u8"),
            E.e("phase", 4, __type: "u8"),
            E.e("rule_type", 0, __type: "u8"),
            E.e("start", current_time - 600, __type: "u32"),
            E.e("end", current_time + 600, __type: "u32")
          ])
        ] ++
        (for {mid, index} <- Enum.with_index(unlock) do
           E.e("arena_reward", [
             E.e("index", index, __type: "s32"),
             E.e("cube_num", (index + 1) * 50, __type: "s32"),
             E.e("kind", 0, __type: "s32"),
             E.e("value", mid, __type: "str")
           ])
         end) ++
        (for sp_dp <- [0, 1], arena_class <- 0..19 do
           E.e("arena_music_difficult", [
             E.e("play_style", sp_dp, __type: "s32"),
             E.e("arena_class", arena_class, __type: "s32"),
             E.e("low_difficult", 8, __type: "s32"),
             E.e("high_difficult", 12, __type: "s32"),
             E.e("is_leggendaria", 1, __type: "bool"),
             E.e("force_music_list_id", 0, __type: "s32")
           ])
         end) ++
        (for sp_dp <- [0, 1], arena_class <- 0..19 do
           E.e("arena_cpu_define", [
             E.e("play_style", sp_dp, __type: "s32"),
             E.e("arena_class", arena_class, __type: "s32"),
             E.e("grade_id", 18, __type: "s32"),
             E.e("low_music_difficult", 8, __type: "s32"),
             E.e("high_music_difficult", 12, __type: "s32"),
             E.e("is_leggendaria", 0, __type: "bool")
           ])
         end) ++
        (for sp_dp <- [0, 1], arena_class <- 0..19 do
           E.e("maching_class_range", [
             E.e("play_style", sp_dp, __type: "s32"),
             E.e("matching_class", arena_class, __type: "s32"),
             E.e("low_arena_class", arena_class, __type: "s32"),
             E.e("high_arena_class", arena_class, __type: "s32")
           ])
         end) ++
        [
          E.e("Event1Phase", val: 0),
          E.e("isNewSongAnother12OpenFlg", val: 1),
          E.e("isKiwamiOpenFlg", val: 1),
          E.e("WorldTourismOpenList", val: -1),
          E.e("OldBPLBattleOpenPhase", val: 3),
          E.e("BPLBattleOpenPhase", val: 3)
        ]

    response = E.e("response", E.e("IIDX32gameSystem", children))

    Core.send_response(conn, info, response)
  end
end
