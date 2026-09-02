defmodule BaconNet.Modules.Iidx.Iidx30gamesystem do
  @moduledoc "Port of modules/iidx/iidx30gamesystem.py."

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local2",
      tag: "local2",
      handlers: [
        {"IIDX30gameSystem", "systemInfo", :iidx30gamesystem_systeminfo}
      ]
    }
  end

  def iidx30gamesystem_systeminfo(conn) do
    {info, conn} = Core.process_request(conn)

    unlock = []
    # force unlock LM exclusives to complete unlock all songs server side
    # this makes LM exclusive folder disappear, so just use hex edits
    # unlock = (28073, 28008, 29095, 29094, 29027, 30077, 30076, 30098, 30106, 30107, 30028, 30064, 30027)

    current_time = :os.system_time(:second)

    children =
      (for mid <- unlock do
         E.e("music_open", [
           E.e("music_id", mid, __type: "s32"),
           E.e("kind", 0, __type: "s32")
         ])
       end) ++
        [
          E.e("arena_schedule", [
            E.e("phase", 3, __type: "u8"),
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
          E.e("CommonBossPhase", val: 0),
          E.e("Event1InternalPhase", val: 0),
          E.e("ExtraBossEventPhase", val: 0),
          E.e("isNewSongAnother12OpenFlg", val: 1),
          E.e("gradeOpenPhase", val: 2),
          E.e("isEiseiOpenFlg", val: 1),
          E.e("WorldTourismOpenList", val: -1),
          E.e("BPLBattleOpenPhase", val: 3)
        ]

    response = E.e("response", E.e("IIDX30gameSystem", children))

    Core.send_response(conn, info, response)
  end
end
