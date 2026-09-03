defmodule BaconNet.Modules.Iidx.Iidx29gamesystem do
  @moduledoc false

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local2",
      tag: "local2",
      handlers: [
        {"IIDX29gameSystem", "systemInfo", :iidx29gamesystem_systeminfo}
      ]
    }
  end

  def iidx29gamesystem_systeminfo(conn) do
    {info, conn} = Core.process_request(conn)

    # (28008, 28065, 28073, 28088, 28089, 29027, 29094, 29095)
    unlock = []
    sp_dp = [0, 1]

    children =
      [
        E.e("arena_schedule", [
          E.e("phase", 2, __type: "u8"),
          E.e("start", 1_605_784_800, __type: "u32"),
          E.e("end", 1_605_871_200, __type: "u32")
        ]),
        E.e("CommonBossPhase", val: 0),
        E.e("Event1InternalPhase", val: 0),
        E.e("ExtraBossEventPhase", val: 0),
        E.e("isNewSongAnother12OpenFlg", val: 1),
        E.e("gradeOpenPhase", val: 2),
        E.e("isEiseiOpenFlg", val: 1),
        E.e("WorldTourismOpenList", val: 1),
        E.e("BPLBattleOpenPhase", val: 2)
      ] ++
        for s <- unlock do
          E.e("music_open", [
            E.e("music_id", s, __type: "s32"),
            E.e("kind", 0, __type: "s32")
          ])
        end ++
        for {s, index} <- Enum.with_index(unlock) do
          E.e("arena_reward", [
            E.e("index", index, __type: "s32"),
            E.e("cube_num", (index + 1) * 50, __type: "s32"),
            E.e("kind", 0, __type: "s32"),
            E.e("value", s, __type: "str")
          ])
        end ++
        for s <- sp_dp do
          E.e("arena_music_difficult", [
            E.e("play_style", s, __type: "s32"),
            E.e("arena_class", -1, __type: "s32"),
            E.e("low_difficult", 1, __type: "s32"),
            E.e("high_difficult", 12, __type: "s32"),
            E.e("is_leggendaria", 1, __type: "bool"),
            E.e("force_music_list_id", 0, __type: "s32")
          ])
        end ++
        for s <- sp_dp do
          E.e("arena_cpu_define", [
            E.e("play_style", s, __type: "s32"),
            E.e("arena_class", -1, __type: "s32"),
            E.e("grade_id", 18, __type: "s32"),
            E.e("low_music_difficult", 8, __type: "s32"),
            E.e("high_music_difficult", 12, __type: "s32"),
            E.e("is_leggendaria", 0, __type: "bool")
          ])
        end ++
        for {play_style, matching_class} <- [{0, 2}, {0, 1}, {1, 2}, {1, 1}] do
          E.e("maching_class_range", [
            E.e("play_style", play_style, __type: "s32"),
            E.e("matching_class", matching_class, __type: "s32"),
            E.e("low_arena_class", 0, __type: "s32"),
            E.e("high_arena_class", 19, __type: "s32")
          ])
        end ++
        for s <- sp_dp do
          E.e("arena_force_music", [
            E.e("play_style", s, __type: "s32"),
            E.e("force_music_list_id", 0, __type: "s32"),
            E.e("index", 0, __type: "s32"),
            E.e("music_id", 1000, __type: "s32"),
            E.e("note_grade", 0, __type: "s32"),
            E.e("is_active", s, __type: "bool")
          ])
        end

    response = E.e("response", E.e("IIDX29gameSystem", children))

    Core.send_response(conn, info, response)
  end
end
