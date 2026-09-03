defmodule Mix.Tasks.Import.DdrAutomap do
  @moduledoc """
  Import DDR scores from a spice automap XML dump.

      mix import.ddr_automap --automap_xml automap.xml --version 3 --ddr_id 12345678

  --version: 1=A20P, 2=A3, 3=WORLD (automap_xml source version, not destination)

  Scores are written to the PostgreSQL database; import the profile first
  with `mix bacon_net.import_json`.
  """

  use Mix.Task

  alias BaconNet.{DB, Kbinxml, XNode, CP932}

  @shortdoc "Import DDR automap scores into the database"

  @impl true
  def run(args) do
    {opts, _argv, _} =
      OptionParser.parse(args,
        strict: [automap_xml: :string, version: :integer, ddr_id: :string]
      )

    automap_xml = Keyword.get(opts, :automap_xml) || Mix.raise("--automap_xml is required")
    version = Keyword.get(opts, :version, 3)

    ddr_id =
      (Keyword.get(opts, :ddr_id) || Mix.raise("--ddr_id is required"))
      |> String.replace("-", "")
      |> String.to_integer()

    Mix.Task.run("app.start")

    if DB.get("ddr_profile", %{"ddr_id" => ddr_id}) == nil do
      Mix.raise("ERROR: DDR profile #{ddr_id} not in the database")
    end

    {playerdata, game_version} =
      case version do
        3 -> {"playdata_3", 20}
        2 -> {"playerdata_2", 19}
        1 -> {"playerdata", 19}
      end

    scores = parse_scores(automap_xml, version, playerdata)

    total_count = length(scores)

    if total_count == 0 do
      Mix.raise("ERROR: No scores to import")
    end

    for [mcode, difficulty, rank, lamp, score] <- scores do
      IO.puts(
        "mcode: #{mcode}, difficulty: #{difficulty}, rank: #{rank}, score: #{score}, lamp: #{lamp}"
      )

      exscore = 0

      best_conds = %{"ddr_id" => ddr_id, "mcode" => mcode, "difficulty" => difficulty}
      best = DB.get("ddr_scores_best", best_conds) || %{}

      best_score_data = %{
        "game_version" => game_version,
        "ddr_id" => ddr_id,
        "playstyle" => if(difficulty < 5, do: 0, else: 1),
        "mcode" => mcode,
        "difficulty" => difficulty,
        "rank" => min(rank, Map.get(best, "rank", rank)),
        "lamp" => max(lamp, Map.get(best, "lamp", lamp)),
        "score" => max(score, Map.get(best, "score", score)),
        "exscore" => max(exscore, Map.get(best, "exscore", exscore))
      }

      ghost_conds = %{
        "ddr_id" => ddr_id,
        "mcode" => mcode,
        "difficulty" => difficulty,
        "score" => max(score, Map.get(best, "score", score))
      }

      ghostid =
        case DB.search_with_ids("ddr_scores", ghost_conds) do
          [{doc_id, _} | _] -> String.to_integer(doc_id)
          [] -> -1
        end

      best_score_data = Map.put(best_score_data, "ghostid", ghostid)

      DB.upsert("ddr_scores_best", best_score_data, best_conds)
    end

    IO.puts("")
    IO.puts("#{total_count} scores imported to DDR profile #{ddr_id}")
  end

  defp parse_scores(automap_xml, version, playerdata) do
    automap_xml
    |> File.read!()
    |> :binary.split("\n\n", [:global])
    |> Enum.reduce_while({[], false}, fn chunk, {scores, scores_xml} ->
      with {:ok, root} <- parse_chunk(chunk) do
        pd = XNode.child(root, playerdata)

        case {version, scores_xml, pd} do
          {v, true, pd} when v in [1, 2] and pd != nil ->
            new =
              for music <- XNode.children(pd, "music") do
                mcode = music |> XNode.child("mcode") |> Map.get(:text) |> String.to_integer()

                music
                |> XNode.children("note")
                |> Enum.with_index()
                |> Enum.flat_map(fn {chart, difficulty} ->
                  c = XNode.child(chart, "count")

                  if c != nil and String.to_integer(c.text || "0") > 0 do
                    rank = chart |> XNode.child("rank") |> Map.get(:text) |> String.to_integer()

                    clearkind =
                      chart |> XNode.child("clearkind") |> Map.get(:text) |> String.to_integer()

                    score = chart |> XNode.child("score") |> Map.get(:text) |> String.to_integer()
                    [[mcode, difficulty, rank, clearkind, score]]
                  else
                    []
                  end
                end)
              end
              |> Enum.flat_map(& &1)

            {:halt, {scores ++ new, false}}

          {3, true, pd} when pd != nil ->
            new =
              for music <- XNode.children(pd, "score") do
                mcode = music |> XNode.child("mcode") |> Map.get(:text) |> String.to_integer()

                (XNode.children(music, "score_single") ++ XNode.children(music, "score_double"))
                |> Enum.flat_map(fn x ->
                  s =
                    x
                    |> XNode.child("score_str")
                    |> Map.get(:text)
                    |> String.split(",")
                    |> Enum.map(&String.to_integer/1)

                  difficulty =
                    if x.tag == "score_double", do: Enum.at(s, 0) + 4, else: Enum.at(s, 0)

                  rank = Enum.at(s, 2)
                  clearkind = Enum.at(s, 3)
                  score = Enum.at(s, 4)
                  [[mcode, difficulty, rank, clearkind, score]]
                end)
              end
              |> Enum.flat_map(& &1)

            {:halt, {scores ++ new, false}}

          {v, false, pd} when v in [1, 2] and pd != nil ->
            mode = pd |> XNode.child("data") |> child_text("mode")
            refid = pd |> XNode.child("data") |> child_text("refid")

            if mode == "userload" and refid != nil and String.length(refid) == 16 do
              {:cont, {scores, true}}
            else
              {:cont, {scores, false}}
            end

          {3, false, pd} when pd != nil ->
            refid = pd |> XNode.child("data") |> child_text("refid")

            if XNode.attr(pd, "method") == "playerdata_load" and refid != nil and
                 String.length(refid) == 16 do
              {:cont, {scores, true}}
            else
              {:cont, {scores, false}}
            end

          _ ->
            {:cont, {scores, scores_xml}}
        end
      else
        _ -> {:cont, {scores, scores_xml}}
      end
    end)
    |> elem(0)
  end

  defp child_text(nil, _tag), do: nil

  defp child_text(node, tag) do
    case XNode.child(node, tag) do
      nil -> nil
      child -> child.text
    end
  end

  defp parse_chunk(chunk) do
    decoded = CP932.decode!(chunk)
    {:ok, Kbinxml.from_text(decoded).node}
  rescue
    _ -> :error
  end
end
