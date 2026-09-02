defmodule BaconNet.Modules.Iidx.Iidx33music do
  @moduledoc "Port of modules/iidx/iidx33music.py."

  alias BaconNet.{Config, Core, DB, E, XNode}

  # ClearFlags: NO_PLAY 0, FAILED 1, ASSIST_CLEAR 2, EASY_CLEAR 3, CLEAR 4,
  # HARD_CLEAR 5, EX_HARD_CLEAR 6, FULL_COMBO 7
  @easy_clear 3
  @full_combo 7

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"IIDX33music", "getrank", :iidx33music_getrank},
        {"IIDX33music", "crate", :iidx33music_crate},
        {"IIDX33music", "reg", :iidx33music_reg},
        {"IIDX33music", "appoint", :iidx33music_appoint},
        {"IIDX33music", "arenaCPU", :iidx33music_arenacpu},
        {"IIDX33music", "retry", :iidx33music_retry},
        {"IIDX33music", "play", :iidx33music_play},
        {"IIDX33music", "nosave", :iidx33music_nosave},
        {"IIDX33music", "getranksub", :iidx33music_getranksub},
        {"IIDX33music", "movieinfo", :iidx33music_movieinfo}
      ]
    }
  end

  def iidx33music_getrank(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version
    node = Core.module_node(info)

    play_style = XNode.attr_int(node, "cltype")

    requested_ids = [
      XNode.attr_int(node, "iidxid", 0),
      XNode.attr_int(node, "iidxid0", 0),
      XNode.attr_int(node, "iidxid1", 0),
      XNode.attr_int(node, "iidxid2", 0),
      XNode.attr_int(node, "iidxid3", 0),
      XNode.attr_int(node, "iidxid4", 0),
      XNode.attr_int(node, "iidxid5", 0)
    ]

    {all_scores, order} =
      requested_ids
      |> Enum.with_index(-1)
      |> Enum.reduce({%{}, []}, fn {iidxid, rival_idx}, acc ->
        if iidxid == 0 do
          acc
        else
          _profile =
            DB.get("iidx_profile", %{"iidx_id" => iidxid})["version"][to_string(game_version)]

          records =
            DB.search("iidx_scores_best", %{
              "play_style" => play_style,
              "iidx_id" => iidxid
            })
            |> Enum.filter(fn record -> record["music_id"] < (game_version + 1) * 1000 end)

          Enum.reduce(records, acc, fn record, {all_scores, order} ->
            music_id = record["music_id"]
            clear_flg = record["clear_flg"]
            ex_score = record["ex_score"]
            miss_count = record["miss_count"]
            chart_id = record["chart_id"]
            key = {rival_idx, music_id}

            {all_scores, order} = ensure_key(all_scores, order, key, default_charts(5))

            entry =
              all_scores[key]
              |> put_in([chart_id, "clear_flg"], clear_flg)
              |> put_in([chart_id, "ex_score"], ex_score)
              |> put_in([chart_id, "miss_count"], miss_count)

            {Map.put(all_scores, key, entry), order}
          end)
        end
      end)

    names =
      Map.new(DB.all("iidx_profile"), fn p ->
        name =
          case get_in(p, ["version", to_string(game_version), "djname"]) do
            nil -> "UNK"
            djname -> djname
          end

        {p["iidx_id"], name}
      end)

    top_records =
      DB.search("iidx_scores_best", %{"play_style" => play_style})
      |> Enum.filter(fn record -> record["music_id"] < (game_version + 1) * 1000 end)

    {top_scores, top_order} =
      Enum.reduce(top_records, {%{}, []}, fn record, {top_scores, top_order} ->
        music_id = record["music_id"]
        ex_score = record["ex_score"]
        chart_id = record["chart_id"]
        iidx_id = record["iidx_id"]

        {top_scores, top_order} = ensure_key(top_scores, top_order, music_id, default_top(5))

        entry =
          if ex_score > top_scores[music_id][chart_id]["ex_score"] do
            put_in(top_scores[music_id], [chart_id], %{
              "djname" => Map.fetch!(names, iidx_id),
              "clear_flg" => 1,
              "ex_score" => ex_score
            })
          else
            top_scores[music_id]
          end

        {Map.put(top_scores, music_id, entry), top_order}
      end)

    m_nodes =
      Enum.map(order, fn {i, k} ->
        charts = all_scores[{i, k}]

        values =
          [i, k] ++
            Enum.map(0..4, fn d -> charts[d]["clear_flg"] end) ++
            Enum.map(0..4, fn d -> charts[d]["ex_score"] end) ++
            Enum.map(0..4, fn d -> charts[d]["miss_count"] end)

        E.e("m", values, __type: "s32")
      end)

    top_nodes =
      Enum.map(top_order, fn k ->
        top = top_scores[k]

        detail =
          [k] ++
            Enum.map(0..4, fn d -> top[d]["clear_flg"] end) ++
            Enum.map(0..4, fn d -> top[d]["ex_score"] end)

        E.e(
          "top",
          E.e("detail", detail, __type: "s32"),
          name0: top[0]["djname"],
          name1: top[1]["djname"],
          name2: top[2]["djname"],
          name3: top[3]["djname"],
          name4: top[4]["djname"]
        )
      end)

    response =
      E.e(
        "response",
        E.e("IIDX33music", [E.e("style", type: play_style)] ++ m_nodes ++ top_nodes)
      )

    Core.send_response(conn, info, response)
  end

  def iidx33music_crate(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    all_score_stats =
      DB.all("iidx_score_stats")
      |> Enum.filter(fn stat -> stat["music_id"] < (game_version + 1) * 1000 end)

    {crate, fcrate, order} =
      Enum.reduce(all_score_stats, {%{}, %{}, []}, fn stat, {crate, fcrate, order} ->
        music_id = stat["music_id"]

        {crate, order} = ensure_key(crate, order, music_id, List.duplicate(1001, 10))
        fcrate = Map.put_new(fcrate, music_id, List.duplicate(1001, 10))

        dp_idx = if stat["play_style"] == 1, do: 5, else: 0
        idx = stat["chart_id"] + dp_idx

        crate =
          Map.put(crate, music_id, List.replace_at(crate[music_id], idx, trunc(stat["clear_rate"])))

        fcrate =
          Map.put(
            fcrate,
            music_id,
            List.replace_at(fcrate[music_id], idx, trunc(stat["fc_rate"]))
          )

        {crate, fcrate, order}
      end)

    c_nodes =
      Enum.map(order, fn k ->
        E.e("c", crate[k] ++ fcrate[k], mid: k, __type: "s32")
      end)

    response = E.e("response", E.e("IIDX33music", c_nodes))
    Core.send_response(conn, info, response)
  end

  def iidx33music_reg(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    timestamp = :os.system_time(:millisecond) / 1000

    node = Core.module_node(info)
    log = XNode.child(node, "music_play_log")

    clear_flg = XNode.attr_int(node, "cflg")
    clid = XNode.attr_int(node, "clid")
    is_death = XNode.attr_int(node, "is_death")
    pid = XNode.attr_int(node, "pid")

    play_style = XNode.attr_int(log, "play_style")
    ex_score = XNode.attr_int(log, "ex_score")
    folder_type = XNode.attr_int(log, "folder_type")
    gauge_type = XNode.attr_int(log, "gauge_type")
    graph_type = XNode.attr_int(log, "graph_type")
    great_num = XNode.attr_int(log, "great_num")
    iidx_id = XNode.attr_int(log, "iidx_id")
    miss_num = if is_death == 0, do: XNode.attr_int(log, "miss_num"), else: -1
    mode_type = XNode.attr_int(log, "mode_type")
    music_id = XNode.attr_int(log, "music_id")
    note_id = XNode.attr_int(log, "note_id")
    option1 = XNode.attr_int(log, "option1")
    option2 = XNode.attr_int(log, "option2")
    pgreat_num = XNode.attr_int(log, "pgreat_num")

    ghost = log |> XNode.child("ghost") |> text()
    ghost_gauge = log |> XNode.child("ghost_gauge") |> text()

    DB.insert("iidx_scores", %{
      "timestamp" => timestamp,
      "game_version" => game_version,
      "iidx_id" => iidx_id,
      "pid" => pid,
      "clear_flg" => clear_flg,
      "is_death" => is_death,
      "music_id" => music_id,
      "play_style" => play_style,
      "chart_id" => note_id,
      "pgreat_num" => pgreat_num,
      "great_num" => great_num,
      "ex_score" => ex_score,
      "miss_count" => miss_num,
      "folder_type" => folder_type,
      "gauge_type" => gauge_type,
      "graph_type" => graph_type,
      "mode_type" => mode_type,
      "option1" => option1,
      "option2" => option2,
      "ghost" => ghost,
      "ghost_gauge" => ghost_gauge
    })

    best_conds = %{
      "iidx_id" => iidx_id,
      "play_style" => play_style,
      "music_id" => music_id,
      "chart_id" => note_id
    }

    best_score = DB.get("iidx_scores_best", best_conds) || %{}

    best_miss_count = Map.get(best_score, "miss_count", miss_num)

    miss_count =
      if best_miss_count == -1 or miss_num == -1 do
        max(miss_num, best_miss_count)
      else
        min(miss_num, best_miss_count)
      end

    best_ex_score = Map.get(best_score, "ex_score", ex_score)

    best_score_data = %{
      "game_version" => game_version,
      "iidx_id" => iidx_id,
      "pid" => pid,
      "play_style" => play_style,
      "music_id" => music_id,
      "chart_id" => note_id,
      "miss_count" => miss_count,
      "ex_score" => max(ex_score, best_ex_score),
      "ghost" =>
        if(ex_score >= best_ex_score, do: ghost, else: Map.get(best_score, "ghost", ghost)),
      "ghost_gauge" =>
        if(ex_score >= best_ex_score,
          do: ghost_gauge,
          else: Map.get(best_score, "ghost_gauge", ghost_gauge)
        ),
      "clear_flg" => max(clear_flg, Map.get(best_score, "clear_flg", clear_flg)),
      "gauge_type" =>
        if(ex_score >= best_ex_score,
          do: gauge_type,
          else: Map.get(best_score, "gauge_type", gauge_type)
        )
    }

    DB.upsert("iidx_scores_best", best_score_data, best_conds)

    stats_conds = %{
      "music_id" => music_id,
      "play_style" => play_style,
      "chart_id" => note_id
    }

    score_stats = DB.get("iidx_score_stats", stats_conds) || %{}

    score_stats =
      score_stats
      |> Map.put("game_version", game_version)
      |> Map.put("play_style", play_style)
      |> Map.put("music_id", music_id)
      |> Map.put("chart_id", note_id)
      |> Map.put("play_count", Map.get(score_stats, "play_count", 0) + 1)
      |> Map.put(
        "fc_count",
        Map.get(score_stats, "fc_count", 0) + if(clear_flg == @full_combo, do: 1, else: 0)
      )
      |> Map.put(
        "clear_count",
        Map.get(score_stats, "clear_count", 0) + if(clear_flg >= @easy_clear, do: 1, else: 0)
      )

    score_stats =
      score_stats
      |> Map.put(
        "fc_rate",
        trunc(score_stats["fc_count"] / score_stats["play_count"] * 1000)
      )
      |> Map.put(
        "clear_rate",
        trunc(score_stats["clear_count"] / score_stats["play_count"] * 1000)
      )

    DB.upsert("iidx_score_stats", score_stats, stats_conds)

    ranklist_scores =
      DB.search("iidx_scores_best", %{
        "play_style" => play_style,
        "music_id" => music_id,
        "chart_id" => note_id
      })

    ranked =
      ranklist_scores
      |> Enum.flat_map(fn score ->
        profile = DB.get("iidx_profile", %{"iidx_id" => score["iidx_id"]})

        if profile == nil or not Map.has_key?(profile["version"], to_string(game_version)) do
          []
        else
          game_profile = profile["version"][to_string(game_version)]

          [
            %{
              "opname" => Config.arcade(),
              "name" => game_profile["djname"],
              "pid" => game_profile["region"],
              "back" => Map.get(game_profile, "back", 0),
              "body" => game_profile["body"],
              "face" => game_profile["face"],
              "hair" => game_profile["hair"],
              "hand" => game_profile["hand"],
              "head" => game_profile["head"],
              "dgrade" => game_profile["grade_double"],
              "sgrade" => game_profile["grade_single"],
              "score" => score["ex_score"],
              "iidx_id" => score["iidx_id"],
              "clflg" => score["clear_flg"],
              "myFlg" => score["iidx_id"] == iidx_id
            }
          ]
        end
      end)
      |> Enum.sort_by(fn x -> {x["clflg"], x["score"]} end, :desc)

    {ranklist_data, my_rank} =
      Enum.map_reduce(Enum.with_index(ranked, 1), 0, fn {score, rnum}, my_rank ->
        node =
          E.e("data",
            rnum: rnum,
            opname: score["opname"],
            name: score["name"],
            pid: score["pid"],
            back: score["back"],
            body: score["body"],
            face: score["face"],
            hair: score["hair"],
            hand: score["hand"],
            head: score["head"],
            dgrade: score["dgrade"],
            sgrade: score["sgrade"],
            score: score["score"],
            iidx_id: score["iidx_id"],
            clflg: score["clflg"],
            myFlg: score["myFlg"],
            achieve: 0
          )

        my_rank = if score["myFlg"], do: rnum, else: my_rank

        {node, my_rank}
      end)

    response =
      E.e(
        "response",
        E.e(
          "IIDX33music",
          [
            E.e("ranklist", ranklist_data, total_user_num: length(ranklist_data)),
            E.e("shopdata", rank: my_rank)
          ],
          clid: clid,
          crate: score_stats["clear_rate"],
          frate: score_stats["fc_rate"],
          mid: music_id
        )
      )

    Core.send_response(conn, info, response)
  end

  def iidx33music_appoint(conn) do
    {info, conn} = Core.process_request(conn)
    node = Core.module_node(info)

    iidxid = XNode.attr_int(node, "iidxid")
    music_id = XNode.attr_int(node, "mid")
    chart_id = XNode.attr_int(node, "clid")
    ctype = XNode.attr_int(node, "ctype")
    subtype = XNode.attr(node, "subtype")

    record =
      DB.get("iidx_scores_best", %{
        "iidx_id" => iidxid,
        "music_id" => music_id,
        "chart_id" => chart_id
      })

    vals =
      if record != nil do
        [
          E.e("mydata", record["ghost"],
            score: record["ex_score"],
            __type: "bin",
            __size: div(String.length(record["ghost"]), 2)
          )
        ]
      else
        []
      end

    sdata =
      cond do
        ctype == 1 ->
          DB.get("iidx_scores_best", %{
            "iidx_id" => String.to_integer(subtype),
            "music_id" => music_id,
            "chart_id" => chart_id
          })

        ctype in [2, 4, 10] ->
          seed = %{
            "game_version" => 29,
            "ghost" => "",
            "ex_score" => 0,
            "iidx_id" => 0,
            "name" => "",
            "pid" => 13
          }

          DB.search("iidx_scores_best", %{"music_id" => music_id, "chart_id" => chart_id})
          |> Enum.reduce(seed, fn record, sdata ->
            if record["ex_score"] > sdata["ex_score"] do
              %{
                sdata
                | "game_version" => record["game_version"],
                  "ghost" => record["ghost"],
                  "ex_score" => record["ex_score"],
                  "iidx_id" => record["iidx_id"],
                  "pid" => record["pid"]
              }
            else
              sdata
            end
          end)

        true ->
          nil
      end

    vals =
      if ctype in [1, 2, 4, 10] and sdata["ex_score"] != 0 do
        name =
          DB.get("iidx_profile", %{"iidx_id" => sdata["iidx_id"]})["version"][
            to_string(sdata["game_version"])
          ]["djname"]

        vals ++
          [
            E.e("sdata", sdata["ghost"],
              score: sdata["ex_score"],
              name: name,
              pid: sdata["pid"],
              __type: "bin",
              __size: div(String.length(sdata["ghost"]), 2)
            )
          ]
      else
        vals
      end

    response = E.e("response", E.e("IIDX33music", vals))
    Core.send_response(conn, info, response)
  end

  def iidx33music_arenacpu(conn) do
    {info, conn} = Core.process_request(conn)
    node = Core.module_node(info)

    music_list = XNode.children(node, "music_list")
    music_count = length(music_list)
    cpu_count = length(XNode.children(node, "cpu_list"))

    cpu =
      Enum.reduce(music_list, %{}, fn music, cpu ->
        music_idx = music |> XNode.child("index") |> text() |> String.to_integer()
        exscore_max = (music |> XNode.child("total_notes") |> text() |> String.to_integer()) * 2

        bots =
          Map.new(py_range(cpu_count), fn bot_idx ->
            exscore = py_round(exscore_max * (0.77 + (0.93 - 0.77) * :rand.uniform()))

            ghost_data =
              Enum.map(0..63, fn x ->
                cell = div(exscore, 64)
                if rem(exscore, 64) > x, do: cell + 1, else: cell
              end)

            {bot_idx, %{"exscore" => exscore, "ghost_data" => ghost_data}}
          end)

        Map.put(cpu, music_idx, bots)
      end)

    response =
      E.e(
        "response",
        E.e(
          "IIDX33music",
          Enum.map(py_range(cpu_count), fn bot_idx ->
            E.e(
              "cpu_score_list",
              [E.e("index", bot_idx, __type: "s32")] ++
                Enum.map(py_range(music_count), fn music_idx ->
                  E.e("score_list", [
                    E.e("index", music_idx, __type: "s32"),
                    E.e("score", cpu[music_idx][bot_idx]["exscore"], __type: "s32"),
                    E.e("ghost", cpu[music_idx][bot_idx]["ghost_data"], __type: "s8"),
                    E.e("enable_score", 1, __type: "bool"),
                    E.e("enable_ghost", 1, __type: "bool"),
                    E.e("location_id", "X000000001", __type: "str")
                  ])
                end)
            )
          end)
        )
      )

    Core.send_response(conn, info, response)
  end

  def iidx33music_retry(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("IIDX33music", [E.e("session", session_id: 1)], status: 0)
      )

    Core.send_response(conn, info, response)
  end

  def iidx33music_play(conn) do
    {info, conn} = Core.process_request(conn)

    response = E.e("response", E.e("IIDX33music"))

    Core.send_response(conn, info, response)
  end

  def iidx33music_nosave(conn) do
    {info, conn} = Core.process_request(conn)

    response = E.e("response", E.e("IIDX33music"))

    Core.send_response(conn, info, response)
  end

  def iidx33music_getranksub(conn) do
    {info, conn} = Core.process_request(conn)

    response = E.e("response", E.e("IIDX33music"))

    Core.send_response(conn, info, response)
  end

  def iidx33music_movieinfo(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("IIDX33music", status: 0)
      )

    Core.send_response(conn, info, response)
  end

  defp default_charts(n) do
    Map.new(0..(n - 1), fn d ->
      {d, %{"clear_flg" => -1, "ex_score" => -1, "miss_count" => -1}}
    end)
  end

  defp default_top(n) do
    Map.new(0..(n - 1), fn d ->
      {d, %{"djname" => "", "clear_flg" => -1, "ex_score" => -1}}
    end)
  end

  defp ensure_key(map, order, key, default) do
    if Map.has_key?(map, key) do
      {map, order}
    else
      {Map.put(map, key, default), order ++ [key]}
    end
  end

  # Python range(n): empty when n <= 0.
  defp py_range(n) when n <= 0, do: []
  defp py_range(n), do: 0..(n - 1)

  # Python round(): half-to-even, not half-away-from-zero.
  defp py_round(x) when is_float(x) do
    f = Float.floor(x)
    diff = x - f

    cond do
      diff < 0.5 -> trunc(f)
      diff > 0.5 -> trunc(f) + 1
      rem(trunc(f), 2) == 0 -> trunc(f)
      true -> trunc(f) + 1
    end
  end

  defp text(nil), do: nil
  defp text(%XNode{text: t}), do: t
end
