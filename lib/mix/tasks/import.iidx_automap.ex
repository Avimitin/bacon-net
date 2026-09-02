defmodule Mix.Tasks.Import.IidxAutomap do
  @moduledoc """
  Import IIDX scores from a spice automap XML dump
  (utils/db/import_iidx_spice_automap.py counterpart).

      mix import.iidx_automap --automap_xml automap.xml --version 30 \
        --monkey_db db.json --iidx_id 12345678
  """

  use Mix.Task

  alias BaconNet.{DB, Kbinxml, XNode, CP932}

  @shortdoc "Import IIDX automap scores into db.json"

  # ClearFlags enum: NO_PLAY=0 FAILED=1 ASSIST_CLEAR=2 EASY_CLEAR=3 CLEAR=4
  # HARD_CLEAR=5 EX_HARD_CLEAR=6 FULL_COMBO=7 (only the used ones are bound)
  @assist_clear 2
  @easy_clear 3
  @full_combo 7

  @default_ghost String.duplicate("0", 104)
  @default_ghost_gauge String.duplicate("0", 1352)

  @impl true
  def run(args) do
    {opts, _argv, _} =
      OptionParser.parse(args,
        strict: [automap_xml: :string, version: :integer, monkey_db: :string, iidx_id: :string]
      )

    automap_xml = Keyword.get(opts, :automap_xml) || Mix.raise("--automap_xml is required")
    version = Keyword.get(opts, :version, 30)
    monkey_db = Keyword.get(opts, :monkey_db) || Mix.raise("--monkey_db is required")

    iidx_id =
      (Keyword.get(opts, :iidx_id) || Mix.raise("--iidx_id is required"))
      |> String.replace("-", "")
      |> String.to_integer()

    Application.put_env(:bacon_net, :db_path, monkey_db)
    {:ok, _} = DB.start_link()

    if DB.get("iidx_profile", %{"iidx_id" => iidx_id}) == nil do
      Mix.raise("ERROR: IIDX profile #{iidx_id} not in #{monkey_db}")
    end

    game_version = 30

    scores = parse_scores(automap_xml, version)

    total_count = length(scores)

    if total_count == 0 do
      Mix.raise("ERROR: No scores to import")
    end

    for [play_style, music_id, difficulty, clear_flg, ex_score, miss_count] <- scores do
      IO.puts(
        "music_id: #{music_id}, sp_dp: #{play_style}, difficulty: #{difficulty}, clear_flg: #{clear_flg}, ex_score: #{ex_score}, miss_count: #{miss_count}"
      )

      best_conds = %{
        "iidx_id" => iidx_id,
        "play_style" => play_style,
        "music_id" => music_id,
        "chart_id" => difficulty
      }

      best_score = DB.get("iidx_scores_best", best_conds) || %{}

      miss_count = if clear_flg < @easy_clear, do: -1, else: miss_count
      best_miss_count = Map.get(best_score, "miss_count", miss_count)

      miss_count =
        cond do
          best_miss_count == -1 -> max(miss_count, best_miss_count)
          clear_flg > @assist_clear -> min(miss_count, best_miss_count)
          true -> best_miss_count
        end

      best_ex_score = Map.get(best_score, "ex_score", ex_score)

      best_score_data = %{
        "game_version" => game_version,
        "iidx_id" => iidx_id,
        "pid" => 13,
        "play_style" => play_style,
        "music_id" => music_id,
        "chart_id" => difficulty,
        "miss_count" => miss_count,
        "ex_score" => max(ex_score, best_ex_score),
        "ghost" => Map.get(best_score, "ghost", @default_ghost),
        "ghost_gauge" => Map.get(best_score, "ghost_gauge", @default_ghost_gauge),
        "clear_flg" => max(clear_flg, Map.get(best_score, "clear_flg", clear_flg)),
        "gauge_type" => Map.get(best_score, "gauge_type", 4)
      }

      DB.upsert("iidx_scores_best", best_score_data, best_conds)

      stats_conds = %{
        "music_id" => music_id,
        "play_style" => play_style,
        "chart_id" => difficulty
      }

      score_stats = DB.get("iidx_score_stats", stats_conds) || %{}

      play_count = Map.get(score_stats, "play_count", 0) + 1

      fc_count =
        Map.get(score_stats, "fc_count", 0) + if(clear_flg == @full_combo, do: 1, else: 0)

      clear_count =
        Map.get(score_stats, "clear_count", 0) + if(clear_flg >= @easy_clear, do: 1, else: 0)

      score_stats =
        score_stats
        |> Map.put("game_version", game_version)
        |> Map.put("play_style", play_style)
        |> Map.put("music_id", music_id)
        |> Map.put("chart_id", difficulty)
        |> Map.put("play_count", play_count)
        |> Map.put("fc_count", fc_count)
        |> Map.put("clear_count", clear_count)
        |> Map.put("fc_rate", trunc(fc_count / play_count * 1000))
        |> Map.put("clear_rate", trunc(clear_count / play_count * 1000))

      DB.upsert("iidx_score_stats", score_stats, stats_conds)
    end

    IO.puts("")
    IO.puts("#{total_count} scores imported to IIDX profile #{iidx_id} in #{monkey_db}")
  end

  defp parse_scores(automap_xml, version) do
    music_tag = "IIDX#{version}music"

    automap_xml
    |> File.read!()
    |> :binary.split("\n\n", [:global])
    |> Enum.reduce({[], false}, fn chunk, {scores, scores_xml} ->
      with {:ok, root} <- parse_chunk(chunk) do
        music = XNode.child(root, music_tag)

        cond do
          scores_xml ->
            sp_dp = music |> XNode.child("style") |> XNode.attr("type") |> String.to_integer()
            IO.puts(sp_dp)

            new =
              for m <- XNode.children(music, "m"), m.text != nil do
                score =
                  m.text |> String.split(~r/\s+/, trim: true) |> Enum.map(&String.to_integer/1)

                if Enum.at(score, 0) == -1 do
                  music_id = Enum.at(score, 1)

                  for difficulty <- 0..4,
                      d = difficulty + 2,
                      Enum.at(score, d) != -1 do
                    [
                      sp_dp,
                      music_id,
                      difficulty,
                      Enum.at(score, d),
                      Enum.at(score, d + 5),
                      Enum.at(score, d + 10)
                    ]
                  end
                else
                  # skip rivals
                  []
                end
              end
              |> Enum.flat_map(& &1)

            {scores ++ new, false}

          music != nil and XNode.attr(music, "method") == "getrank" ->
            {scores, true}

          true ->
            {scores, scores_xml}
        end
      else
        _ -> {scores, scores_xml}
      end
    end)
    |> elem(0)
  end

  defp parse_chunk(chunk) do
    decoded = CP932.decode!(chunk)
    {:ok, Kbinxml.from_text(decoded).node}
  rescue
    _ -> :error
  end
end
