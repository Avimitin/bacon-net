defmodule BaconNet.Modules.Iidx.Music do
  @moduledoc "Port of modules/iidx/music.py."

  alias BaconNet.{Config, Core, DB, E, XNode}

  # ClearFlags: NO_PLAY 0, FAILED 1, ASSIST_CLEAR 2, EASY_CLEAR 3, CLEAR 4,
  # HARD_CLEAR 5, EX_HARD_CLEAR 6, FULL_COMBO 7
  @assist_clear 2
  @easy_clear 3
  @full_combo 7

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"music", "getrank", :music_getrank},
        {"music", "crate", :music_crate},
        {"music", "reg", :music_reg},
        {"music", "appoint", :music_appoint}
      ]
    }
  end

  def music_getrank(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version
    node = Core.module_node(info)

    iidxid = XNode.attr_int(node, "iidxid")
    play_style = XNode.attr_int(node, "cltype")

    records =
      DB.search("iidx_scores_best", %{"iidx_id" => iidxid, "play_style" => play_style})
      |> Enum.filter(fn record -> record["music_id"] < (game_version + 1) * 1000 end)

    {all_scores, order} =
      Enum.reduce(records, {%{}, []}, fn record, {all_scores, order} ->
        music_id = record["music_id"]
        clear_flg = record["clear_flg"]

        {music_id, clear_flg} =
          if game_version < 20 do
            m = Integer.to_string(music_id)

            music_id =
              String.to_integer(py_slice_head(m, String.length(m) - 3) <> py_slice_tail(m, 2))

            clear_flg =
              if clear_flg == @full_combo and game_version < 19, do: 6, else: clear_flg

            {music_id, clear_flg}
          else
            {music_id, clear_flg}
          end

        ex_score = record["ex_score"]
        miss_count = record["miss_count"]
        cid = record["chart_id"]

        if cid in [0, 4, 5, 9] do
          {all_scores, order}
        else
          chart_id = cid - 1
          {all_scores, order} = ensure_key(all_scores, order, music_id, default_charts(3))

          entry =
            all_scores[music_id]
            |> put_in([chart_id, "clear_flg"], clear_flg)
            |> put_in([chart_id, "ex_score"], ex_score)
            |> put_in([chart_id, "miss_count"], miss_count)

          {Map.put(all_scores, music_id, entry), order}
        end
      end)

    m_nodes =
      Enum.map(order, fn k ->
        charts = all_scores[k]

        values =
          [-1, k] ++
            Enum.map(0..2, fn d -> charts[d]["clear_flg"] end) ++
            Enum.map(0..2, fn d -> charts[d]["ex_score"] end) ++
            Enum.map(0..2, fn d -> charts[d]["miss_count"] end)

        E.e("m", values, __type: "s16")
      end)

    response = E.e("response", E.e("music", [E.e("style", type: play_style)] ++ m_nodes))
    Core.send_response(conn, info, response)
  end

  def music_crate(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    all_score_stats =
      DB.all("iidx_score_stats")
      |> Enum.filter(fn stat -> stat["music_id"] < (game_version + 1) * 1000 end)

    {crate, fcrate, order} =
      Enum.reduce(all_score_stats, {%{}, %{}, []}, fn stat, {crate, fcrate, order} ->
        music_id = stat["music_id"]

        music_id =
          if game_version < 20 do
            m = Integer.to_string(music_id)
            String.to_integer(py_slice_head(m, String.length(m) - 3) <> py_slice_tail(m, 2))
          else
            music_id
          end

        {crate, order} = ensure_key(crate, order, music_id, List.duplicate(101, 6))
        fcrate = Map.put_new(fcrate, music_id, List.duplicate(101, 6))

        old_to_new_adjust =
          cond do
            stat["play_style"] == 0 -> -1
            stat["play_style"] == 1 -> 2
          end

        idx = stat["chart_id"] + old_to_new_adjust

        crate =
          Map.put(
            crate,
            music_id,
            List.replace_at(crate[music_id], idx, div(trunc(stat["clear_rate"]), 10))
          )

        fcrate =
          Map.put(
            fcrate,
            music_id,
            List.replace_at(fcrate[music_id], idx, div(trunc(stat["fc_rate"]), 10))
          )

        {crate, fcrate, order}
      end)

    c_nodes =
      Enum.map(order, fn k ->
        E.e("c", crate[k] ++ fcrate[k], mid: k, __type: "u8")
      end)

    response = E.e("response", E.e("music", c_nodes))
    Core.send_response(conn, info, response)
  end

  def music_reg(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    timestamp = :os.system_time(:millisecond) / 1000

    node = Core.module_node(info)

    clear_flg = XNode.attr_int(node, "cflg")
    clid = XNode.attr_int(node, "clid")
    great_num = XNode.attr_int(node, "gnum")
    iidx_id = XNode.attr_int(node, "iidxid")
    miss_num = XNode.attr_int(node, "mnum")
    pgreat_num = XNode.attr_int(node, "pgnum")
    pid = XNode.attr_int(node, "pid")
    ex_score = pgreat_num * 2 + great_num

    {is_death, music_id, clear_flg} =
      if game_version == 20 do
        {XNode.attr_int(node, "is_death"), XNode.attr_int(node, "mid"), clear_flg}
      else
        is_death = if clear_flg < @assist_clear, do: 1, else: 0
        m = XNode.attr(node, "mid")

        music_id =
          String.to_integer(py_slice_head(m, String.length(m) - 2) <> "0" <> py_slice_tail(m, 2))

        clear_flg =
          if clear_flg == 6 and game_version < 19, do: @full_combo, else: clear_flg

        {is_death, music_id, clear_flg}
      end

    {note_id, play_style} =
      if clid < 3 do
        {clid + 1, 0}
      else
        {clid - 2, 1}
      end

    ghost = node |> XNode.child("ghost") |> text()

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
      "ghost" => ghost
    })

    best_conds = %{
      "iidx_id" => iidx_id,
      "play_style" => play_style,
      "music_id" => music_id,
      "chart_id" => note_id
    }

    best_score = DB.get("iidx_scores_best", best_conds) || %{}

    miss_num = if clear_flg < @easy_clear, do: -1, else: miss_num
    best_miss_count = Map.get(best_score, "miss_count", miss_num)

    miss_count =
      cond do
        best_miss_count == -1 -> max(miss_num, best_miss_count)
        clear_flg > @assist_clear -> min(miss_num, best_miss_count)
        true -> best_miss_count
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
      "ghost_gauge" => Map.get(best_score, "ghost_gauge", 0),
      "clear_flg" => max(clear_flg, Map.get(best_score, "clear_flg", clear_flg)),
      "gauge_type" => Map.get(best_score, "gauge_type", 0)
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
              "body" => Map.get(game_profile, "body", 0),
              "face" => Map.get(game_profile, "face", 0),
              "hair" => Map.get(game_profile, "hair", 0),
              "hand" => Map.get(game_profile, "hand", 0),
              "head" => Map.get(game_profile, "head", 0),
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
          "music",
          [
            E.e("ranklist", ranklist_data, total_user_num: length(ranklist_data)),
            E.e("shopdata", rank: my_rank)
          ],
          clid: clid,
          crate: div(score_stats["clear_rate"], 10),
          frate: div(score_stats["fc_rate"], 10),
          mid: music_id
        )
      )

    Core.send_response(conn, info, response)
  end

  def music_appoint(conn) do
    {info, conn} = Core.process_request(conn)
    node = Core.module_node(info)

    iidxid = XNode.attr_int(node, "iidxid")
    music_id = XNode.attr_int(node, "mid")
    chart_id = XNode.attr_int(node, "clid")

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

    response = E.e("response", E.e("music", vals))
    Core.send_response(conn, info, response)
  end

  defp default_charts(n) do
    Map.new(0..(n - 1), fn d ->
      {d, %{"clear_flg" => -1, "ex_score" => -1, "miss_count" => -1}}
    end)
  end

  defp ensure_key(map, order, key, default) do
    if Map.has_key?(map, key) do
      {map, order}
    else
      {Map.put(map, key, default), order ++ [key]}
    end
  end

  # Python slicing semantics: m[:n] and m[-n:] clamp instead of raising.
  defp py_slice_head(m, n) do
    len = String.length(m)
    stop = if n < 0, do: max(len + n, 0), else: min(n, len)
    String.slice(m, 0, stop)
  end

  defp py_slice_tail(m, n) do
    len = String.length(m)
    String.slice(m, max(len - n, 0), n)
  end

  defp text(nil), do: nil
  defp text(%XNode{text: t}), do: t
end
