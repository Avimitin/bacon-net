defmodule BaconNet.Modules.Iidx.ScoreSave do
  @moduledoc """
  Shared transactional score save for the IIDX music `reg` handlers
  (iidx29music–iidx33music via `save/2`, and the legacy shared `music`
  module via `save_legacy/2`).

  Both wrap `BaconNet.Scores.record_attempt/2`: one transaction claims the
  idempotency key, inserts the immutable attempt, upserts the relational
  best with the per-game SQL merge, bumps stats, appends the outbox event,
  and dual-writes the legacy document tables (`iidx_scores`,
  `iidx_scores_best`, `iidx_score_stats`) that the iidx api/pc modules and
  older versions still read. The legacy merge logic below is kept verbatim
  from the original handlers; the relational best_scores row lock serializes
  writers per player+chart, so the read-modify-write merge cannot lose
  updates.

  Returns `{:ok, score_stats_doc}` (the dual-written stats document, for the
  crate/frate response attributes) or `{:error, reason}`. On `{:error, _}`
  the caller must send an error response, never a success body.
  """

  alias BaconNet.{DB, Scores}
  alias BaconNet.Scores.Merge

  # ClearFlags: NO_PLAY 0, FAILED 1, ASSIST_CLEAR 2, EASY_CLEAR 3, CLEAR 4,
  # HARD_CLEAR 5, EX_HARD_CLEAR 6, FULL_COMBO 7
  @assist_clear 2
  @easy_clear 3
  @full_combo 7

  @doc """
  Record one play in the v29+ shape. `fields` keys: `:game_version`,
  `:iidx_id`, `:pid`, `:play_style`, `:music_id`, `:note_id`, `:clear_flg`,
  `:ex_score`, `:miss_num`, `:ghost`, `:ghost_gauge`, `:gauge_type`,
  `:attempt_doc`.
  """
  def save(info, fields) do
    event = %{
      game: "iidx",
      version: fields.game_version,
      player: to_string(fields.iidx_id),
      song: fields.music_id,
      chart: fields.note_id,
      play_style: to_string(fields.play_style),
      score: fields.ex_score,
      clear: fields.clear_flg,
      miss: fields.miss_num,
      payload: %{
        "ghost" => fields.ghost,
        "ghost_gauge" => fields.ghost_gauge,
        "gauge_type" => fields.gauge_type,
        "game_version" => fields.game_version,
        "pid" => fields.pid
      },
      attempt: fields.attempt_doc,
      stats: %{clear: fields.clear_flg >= @easy_clear, fc: fields.clear_flg == @full_combo},
      merge: Merge.spec("iidx"),
      idempotency: idempotency(info, fields.iidx_id),
      dual_write: fn _recorded -> dual_write(fields) end
    }

    record(event)
  end

  @doc """
  Record one play in the legacy (<= v20) `music` module shape: no ghost_gauge
  in the request, and the miss merge also considers the clear flag.
  """
  def save_legacy(info, fields) do
    # The legacy merge only keeps a miss count for cleared plays; the attempt
    # document keeps the raw value.
    miss_num = if fields.clear_flg < @easy_clear, do: -1, else: fields.miss_num

    fields = Map.put(fields, :miss_num, miss_num)

    event = %{
      game: "iidx",
      version: fields.game_version,
      player: to_string(fields.iidx_id),
      song: fields.music_id,
      chart: fields.note_id,
      play_style: to_string(fields.play_style),
      score: fields.ex_score,
      clear: fields.clear_flg,
      miss: miss_num,
      payload: %{
        "ghost" => fields.ghost,
        "ghost_gauge" => 0,
        "gauge_type" => 0,
        "game_version" => fields.game_version,
        "pid" => fields.pid
      },
      attempt: fields.attempt_doc,
      stats: %{clear: fields.clear_flg >= @easy_clear, fc: fields.clear_flg == @full_combo},
      merge: Merge.spec("iidx_legacy"),
      idempotency: idempotency(info, fields.iidx_id),
      dual_write: fn _recorded -> dual_write_legacy(fields) end
    }

    record(event)
  end

  defp idempotency(info, iidx_id) do
    scope = "#{info.module}.#{info.method}"

    %{
      key: Scores.derive_key("iidx", scope, iidx_id, info.text),
      scope: scope,
      payload_hash: Scores.hash_payload(info.text)
    }
  end

  defp record(event) do
    case Scores.record_attempt(event) do
      {:ok, %{status: :recorded, extra: score_stats}} -> {:ok, score_stats}
      {:ok, %{status: :replayed, response: response}} -> {:ok, response["extra"]}
      {:error, reason} -> {:error, reason}
    end
  end

  # Dual-write for the v29+ shape (identical merge in iidx29-33 before the
  # transactional port).
  defp dual_write(fields) do
    %{
      game_version: game_version,
      iidx_id: iidx_id,
      pid: pid,
      play_style: play_style,
      music_id: music_id,
      note_id: note_id,
      clear_flg: clear_flg,
      ex_score: ex_score,
      miss_num: miss_num,
      ghost: ghost,
      ghost_gauge: ghost_gauge,
      gauge_type: gauge_type,
      attempt_doc: attempt_doc
    } = fields

    DB.insert("iidx_scores", attempt_doc)

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

    bump_stats_doc(game_version, play_style, music_id, note_id, clear_flg)
  end

  # Dual-write for the legacy music module: ghost_gauge/gauge_type are
  # carried from the old best, and the miss rule considers the clear flag.
  defp dual_write_legacy(fields) do
    %{
      game_version: game_version,
      iidx_id: iidx_id,
      pid: pid,
      play_style: play_style,
      music_id: music_id,
      note_id: note_id,
      clear_flg: clear_flg,
      ex_score: ex_score,
      miss_num: miss_num,
      ghost: ghost,
      attempt_doc: attempt_doc
    } = fields

    DB.insert("iidx_scores", attempt_doc)

    best_conds = %{
      "iidx_id" => iidx_id,
      "play_style" => play_style,
      "music_id" => music_id,
      "chart_id" => note_id
    }

    best_score = DB.get("iidx_scores_best", best_conds) || %{}

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

    bump_stats_doc(game_version, play_style, music_id, note_id, clear_flg)
  end

  # The iidx_score_stats document (read by crate handlers and iidx*pc):
  # read-modify-write, serialized per chart by the relational score_stats
  # row lock taken just before this hook runs.
  defp bump_stats_doc(game_version, play_style, music_id, note_id, clear_flg) do
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

    score_stats
  end
end
