defmodule BaconNet.Modules.Iidx.Iidx30grade do
  @moduledoc "Port of modules/iidx/iidx30grade.py."

  alias BaconNet.{Core, DB, E, XNode}

  def routes do
    %{
      prefix: "/local2",
      tag: "local2",
      handlers: [
        {"IIDX30grade", "raised", :iidx30grade_raised}
      ]
    }
  end

  defp get_profile(iidx_id) do
    DB.get("iidx_profile", %{"iidx_id" => iidx_id})
  end

  def iidx30grade_raised(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    timestamp = :os.system_time(:millisecond) / 1000

    node = Core.module_node(info)
    iidx_id = XNode.attr_int(node, "iidxid")
    achi = XNode.attr_int(node, "achi")
    cstage = XNode.attr_int(node, "cstage")
    gid = XNode.attr_int(node, "gid")
    gtype = XNode.attr_int(node, "gtype")
    is_ex = XNode.attr_int(node, "is_ex")
    is_mirror = XNode.attr_int(node, "is_mirror")

    DB.insert("iidx_class", %{
      "timestamp" => timestamp,
      "game_version" => game_version,
      "iidx_id" => iidx_id,
      "achi" => achi,
      "cstage" => cstage,
      "gid" => gid,
      "gtype" => gtype,
      "is_ex" => is_ex,
      "is_mirror" => is_mirror
    })

    profile = get_profile(iidx_id)
    game_profile = get_in(profile, ["version", to_string(game_version)]) || %{}

    best_class =
      DB.get("iidx_class_best", %{
        "iidx_id" => iidx_id,
        "game_version" => game_version,
        "gid" => gid,
        "gtype" => gtype
      }) || %{}

    best_class_data = %{
      "game_version" => game_version,
      "iidx_id" => iidx_id,
      "achi" => max(achi, Map.get(best_class, "achi", achi)),
      "cstage" => max(cstage, Map.get(best_class, "cstage", cstage)),
      "gid" => gid,
      "gtype" => gtype,
      "is_ex" => is_ex,
      "is_mirror" => is_mirror
    }

    DB.upsert("iidx_class_best", best_class_data, %{
      "iidx_id" => iidx_id,
      "game_version" => game_version,
      "gid" => gid,
      "gtype" => gtype
    })

    best_class_plays =
      DB.search("iidx_class_best", %{"game_version" => game_version, "iidx_id" => iidx_id})

    grades =
      Enum.map(best_class_plays, fn record ->
        [record["gtype"], record["gid"], record["cstage"], record["achi"]]
      end)

    game_profile = Map.put(game_profile, "grade_values", grades)

    grade_sp =
      DB.search("iidx_class_best", %{
        "game_version" => game_version,
        "iidx_id" => iidx_id,
        "gtype" => 0,
        "cstage" => 4
      })

    game_profile =
      Map.put(
        game_profile,
        "grade_single",
        Enum.max(Enum.map(grade_sp, & &1["gid"]), fn -> -1 end)
      )

    grade_dp =
      DB.search("iidx_class_best", %{
        "game_version" => game_version,
        "iidx_id" => iidx_id,
        "gtype" => 1,
        "cstage" => 4
      })

    game_profile =
      Map.put(
        game_profile,
        "grade_double",
        Enum.max(Enum.map(grade_dp, & &1["gid"]), fn -> -1 end)
      )

    profile = put_in(profile, ["version", to_string(game_version)], game_profile)

    DB.upsert("iidx_profile", profile, %{"game_version" => game_version})

    Core.send_response(conn, info, E.e("response", E.e("IIDX30grade", pnum: 1)))
  end
end
