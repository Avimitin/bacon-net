defmodule BaconNet.Scores.Merge do
  @moduledoc """
  Per-game best-score merge rules, expressed as data.

  A merge spec:

      %{
        miss: :iidx | :least | :ignore,
        payload_max: [binary],           # greatest wins
        payload_min: [binary],           # least wins (e.g. DDR rank)
        payload_follow_score: [binary],  # taken from the side with the best
                                         # primary score; ties (>=) go to the new play
        payload_overwrite: [binary]      # always taken from the new play
      }

  The same spec drives both implementations of the merge:

    * `merge/3` — a pure Elixir function, unit-testable without a database.
    * `update_set_sql/1` — the SET clause of the single-statement
      `INSERT ... ON CONFLICT DO UPDATE` used by `BaconNet.Scores.upsert_best!/1`,
      so concurrent submissions merge atomically inside the database.

  `BaconNet.ScoresTest` cross-checks the two implementations against each
  other. Every payload key a game writes should be listed in its spec;
  unlisted keys are written on insert and never merged afterwards.
  """

  @gitadora %{
    miss: :ignore,
    payload_max: ["excellent", "fullcombo", "rank", "skill"],
    payload_min: [],
    payload_follow_score: ["meter", "meter_prog"],
    payload_overwrite: []
  }

  @specs %{
    "iidx" => %{
      miss: :iidx,
      payload_max: [],
      payload_min: [],
      payload_follow_score: ["gauge_type", "ghost", "ghost_gauge"],
      payload_overwrite: ["game_version", "pid"]
    },
    # Legacy IIDX (the shared `music` module, versions <= 20): the miss rule
    # also looks at the new play's clear flag, and ghost_gauge/gauge_type are
    # carried from the old best (unlisted payload keys never change).
    "iidx_legacy" => %{
      miss: :iidx_legacy,
      payload_max: [],
      payload_min: [],
      payload_follow_score: ["ghost"],
      payload_overwrite: ["game_version", "pid"]
    },
    "ddr" => %{
      miss: :ignore,
      payload_max: ["exscore", "flare_force"],
      payload_min: ["rank"],
      payload_follow_score: ["ghost", "ghostsize"],
      payload_overwrite: ["game_version", "playstyle"]
    },
    # DDR A20/A3 (playerdata/playerdata_2 usersave): no flare force yet.
    "ddr_legacy" => %{
      miss: :ignore,
      payload_max: ["exscore"],
      payload_min: ["rank"],
      payload_follow_score: ["ghost", "ghostsize"],
      payload_overwrite: ["game_version", "playstyle"]
    },
    "sdvx" => %{
      miss: :ignore,
      payload_max: ["btn_rate", "exscore", "long_rate", "score_grade", "vol_rate"],
      payload_min: [],
      payload_follow_score: [],
      payload_overwrite: ["game_version", "name"]
    },
    "drs" => %{
      miss: :ignore,
      payload_max: ["combo", "rank"],
      payload_min: [],
      payload_follow_score: [],
      payload_overwrite: ["game_version", "name", "param"]
    },
    "nostalgia" => %{
      miss: :ignore,
      payload_max: ["clear_flag", "grade", "hands_mode"],
      payload_min: [],
      payload_follow_score: [],
      payload_overwrite: ["clear_count", "game_version", "multi_count", "play_count"]
    },
    "guitarfreaks" => @gitadora,
    "drummania" => @gitadora
  }

  @field_re ~r/^[a-z0-9_]+$/

  @doc "The merge spec for a game. Raises for an unknown game."
  def spec(game), do: Map.fetch!(@specs, game)

  @doc "All known merge specs."
  def specs, do: @specs

  @doc """
  Pure mirror of the SQL upsert merge. `old`/`new` are maps with `:score`,
  `:clear`, `:miss` and `:payload` keys; `old` is nil when no best row
  exists yet. Returns the merged row in the same shape.
  """
  def merge(_spec, nil, new), do: new

  def merge(spec, old, new) do
    %{
      score: max(old.score, new.score),
      clear: max(old.clear, new.clear),
      miss: merge_miss(spec.miss, old, new),
      payload: merge_payload(spec, old, new)
    }
  end

  defp merge_miss(:iidx, old, new) when old.miss == -1 or new.miss == -1 do
    max(old.miss, new.miss)
  end

  defp merge_miss(:iidx, old, new), do: min(old.miss, new.miss)

  # Legacy IIDX: -1 in the stored best adopts the new value; a clear takes
  # the min; otherwise the stored best stands.
  defp merge_miss(:iidx_legacy, old, new) do
    cond do
      old.miss == -1 -> new.miss
      new.clear > 2 -> min(old.miss, new.miss)
      true -> old.miss
    end
  end

  defp merge_miss(:least, old, new), do: min(old.miss, new.miss)
  defp merge_miss(:ignore, old, _new), do: old.miss

  defp merge_payload(spec, old, new) do
    old_p = old.payload
    new_p = new.payload

    old_p
    |> merge_each(spec.payload_max, fn k -> max(Map.fetch!(old_p, k), Map.fetch!(new_p, k)) end)
    |> merge_each(spec.payload_min, fn k -> min(Map.fetch!(old_p, k), Map.fetch!(new_p, k)) end)
    |> merge_each(spec.payload_follow_score, fn k ->
      if new.score >= old.score, do: Map.fetch!(new_p, k), else: Map.fetch!(old_p, k)
    end)
    |> merge_each(spec.payload_overwrite, fn k -> Map.fetch!(new_p, k) end)
  end

  defp merge_each(payload, keys, fun) do
    Enum.reduce(keys, payload, fn k, acc -> Map.put(acc, k, fun.(k)) end)
  end

  @doc """
  The `miss = ...` expression for the best_scores upsert, per merge rule.
  In ON CONFLICT DO UPDATE, `best_scores` refers to the pre-update row.
  """
  def miss_sql(:iidx) do
    "CASE WHEN best_scores.miss = -1 OR excluded.miss = -1 " <>
      "THEN greatest(best_scores.miss, excluded.miss) " <>
      "ELSE least(best_scores.miss, excluded.miss) END"
  end

  def miss_sql(:iidx_legacy) do
    "CASE WHEN best_scores.miss = -1 THEN excluded.miss " <>
      "WHEN excluded.clear > 2 THEN least(best_scores.miss, excluded.miss) " <>
      "ELSE best_scores.miss END"
  end

  def miss_sql(:least), do: "least(best_scores.miss, excluded.miss)"
  def miss_sql(:ignore), do: "best_scores.miss"

  @doc """
  The `payload = ...` expression for the best_scores upsert: the stored
  payload with every spec-listed field merged field-by-field, mirroring
  `merge/3` exactly.
  """
  def payload_sql(spec) do
    base = "best_scores.payload"

    wrap(spec.payload_max, base, fn f ->
      "to_jsonb(greatest(" <>
        "(best_scores.payload->>'#{f}')::bigint, (excluded.payload->>'#{f}')::bigint))"
    end)
    |> then(fn acc ->
      wrap(spec.payload_min, acc, fn f ->
        "to_jsonb(least(" <>
          "(best_scores.payload->>'#{f}')::bigint, (excluded.payload->>'#{f}')::bigint))"
      end)
    end)
    |> then(fn acc ->
      wrap(spec.payload_follow_score, acc, fn f ->
        "CASE WHEN excluded.score >= best_scores.score " <>
          "THEN excluded.payload->'#{f}' ELSE best_scores.payload->'#{f}' END"
      end)
    end)
    |> then(fn acc ->
      wrap(spec.payload_overwrite, acc, fn f -> "excluded.payload->'#{f}'" end)
    end)
  end

  defp wrap(fields, acc, value_sql) do
    Enum.reduce(fields, acc, fn f, acc ->
      validate_field!(f)
      "jsonb_set(#{acc}, '{#{f}}', #{value_sql.(f)})"
    end)
  end

  # Field names are interpolated into SQL; they come from the static specs
  # above, but fail loudly if a spec ever adds an unsafe name.
  defp validate_field!(f) do
    unless f =~ @field_re, do: raise("unsafe best_scores payload field name: #{inspect(f)}")
  end
end
