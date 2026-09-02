defmodule BaconNet.Scores do
  @moduledoc """
  Atomic, idempotent, retry-safe score persistence.

  `record_attempt/2` takes a normalized score event and executes one
  database transaction:

    1. claim the idempotency key (a conflicting claim with the same payload
       returns the recorded prior result and applies no further effects);
    2. insert the immutable `play_attempts` row;
    3. upsert `best_scores` with a monotonic, per-game SQL merge
       (`BaconNet.Scores.Merge`);
    4. bump `score_stats` counters with an atomic
       `INSERT ... ON CONFLICT DO UPDATE SET x = x + 1`;
    5. append a pending `outbox_events` row for leaderboard projections;
    6. run the event's `dual_write` hook, which projects the write into the
       legacy document tables (`iidx_scores_best` etc.) that other modules
       still read.

  Either everything commits or nothing is visible. On any failure the
  caller receives `{:error, reason}` and must produce an error response,
  never a success body.

  ## Idempotency keys

  Cabinets do not send event ids, so the key is derived server-side as
  `sha256(game, method, player key, canonical request body)`
  (`derive_key/4`; the canonical body is the decoded request's normalized
  XML text, so byte-identical submissions hash identically). The recorded
  outcome is stored with the key; a repeated byte-identical submission
  returns the recorded result without duplicate attempts, stats, or outbox
  events. Reusing a key with a *different* payload is rejected with
  `{:error, :idempotency_conflict}`.

  Tradeoff: two genuinely distinct plays that serialize to byte-identical
  requests (same player, chart, score and ghost) collapse into one recorded
  play. Judgement counts and ghost data make that vanishingly unlikely, and
  it is the price of retrofitting idempotency onto a protocol without
  client-supplied event ids. Keys are retained indefinitely today; if a
  retention sweep is ever added, a replay older than the window records
  again.

  ## Failure injection

  `record_attempt/2` accepts a `:stage_hook` option — a `fun(stage)` called
  inside the transaction after each stage (`:claim`, `:attempt`, `:best`,
  `:stats`, `:outbox`, `:dual_write`, `:response`). Tests use it to force a
  rollback at any point. Never set it in production code.
  """

  import Ecto.Query

  alias BaconNet.{DB, Repo}
  alias BaconNet.Scores.{BestScore, IdempotencyKey, Merge, OutboxEvent, PlayAttempt, ScoreStat}

  @doc "Derive an idempotency key from a request's canonical content."
  def derive_key(game, method, player, canonical_body) do
    :crypto.hash(:sha256, [
      to_string(game),
      <<0>>,
      to_string(method),
      <<0>>,
      to_string(player),
      <<0>>,
      canonical_body || ""
    ])
    |> Base.encode16(case: :lower)
  end

  @doc "Hash a request's canonical body for payload-mismatch detection."
  def hash_payload(canonical_body) do
    :crypto.hash(:sha256, canonical_body || "") |> Base.encode16(case: :lower)
  end

  @doc """
  Record one score attempt as a single atomic transaction.

  `event` keys:

    * `:game`, `:version`, `:player` (string key), `:song`, `:chart`,
      `:play_style` (default `""`)
    * `:score`, `:clear`, `:miss` (optional) — generic best-score columns
    * `:payload` — game-specific best-row fields (merged per `:merge`)
    * `:attempt` — full fields stored in the immutable attempt row
    * `:stats` — `%{clear: boolean, fc: boolean}` counter flags
    * `:merge` — a `BaconNet.Scores.Merge` spec
    * `:idempotency` — `%{key:, scope:, payload_hash:}`, or nil (only for
      callers that already claimed a key in an outer transaction)
    * `:dual_write` — optional `fun(recorded)` run in the same transaction
      to project into legacy document tables

  Returns `{:ok, %{status: :recorded, ...}}`, `{:ok, %{status: :replayed,
  response: ...}}`, `{:error, :idempotency_conflict}`, or `{:error, reason}`.
  """
  def record_attempt(event, opts \\ []) do
    hook = Keyword.get(opts, :stage_hook, fn _stage -> :ok end)

    try do
      DB.transaction(fn ->
        case claim_idempotency(event.idempotency) do
          :claimed ->
            hook.(:claim)
            recorded = apply_attempt!(event, hook)
            response = recorded_response(recorded)
            record_response!(event.idempotency.key, response)
            hook.(:response)
            Map.merge(recorded, %{status: :recorded, response: response})

          {:replay, response} ->
            %{status: :replayed, response: response}

          :conflict ->
            DB.rollback(:idempotency_conflict)
        end
      end)
    rescue
      e -> {:error, {:exception, e}}
    end
  end

  @doc """
  Claim an idempotency key inside the current transaction.

  Returns `:claimed`, `{:replay, recorded_response}`, or `:conflict`
  (same key, different payload). A concurrent in-flight claim of the same
  key blocks until that transaction finishes, so a replay always observes
  the fully recorded outcome.
  """
  def claim_idempotency(%{key: key, scope: scope, payload_hash: hash}) do
    {:ok, row} =
      Repo.insert(%IdempotencyKey{key: key, scope: scope, payload_hash: hash},
        on_conflict: :nothing,
        conflict_target: [:key]
      )

    if row.id do
      :claimed
    else
      existing = Repo.get_by!(IdempotencyKey, key: key)

      if existing.payload_hash == hash do
        {:replay, existing.response}
      else
        :conflict
      end
    end
  end

  @doc """
  Apply the write stages of a score attempt inside the current transaction:
  insert the attempt, upsert the best, bump stats, append the outbox event,
  and run the dual-write hook. Use this directly (with an outer
  `DB.transaction/1` and your own `claim_idempotency/1`) when one request
  records several attempts, e.g. gitadora's per-stage loop.
  """
  def apply_attempt!(event, hook \\ fn _stage -> :ok end) do
    attempt = insert_attempt!(event)
    hook.(:attempt)
    best = upsert_best!(event)
    hook.(:best)
    stats = bump_stats!(event)
    hook.(:stats)
    append_outbox!(event, attempt)
    hook.(:outbox)

    extra =
      if dual = event[:dual_write], do: dual.(%{attempt_id: attempt.id, best: best, stats: stats})

    hook.(:dual_write)
    %{attempt_id: attempt.id, best: best, stats: stats, extra: extra}
  end

  @doc "Store the recorded outcome on a claimed idempotency key."
  def record_response!(key, response) do
    {1, _} =
      from(k in IdempotencyKey, where: k.key == ^key)
      |> Repo.update_all(set: [response: response])

    :ok
  end

  @doc "The best row for a key, or nil."
  def get_best(game, player, song, chart, play_style \\ "") do
    Repo.get_by(BestScore,
      game: game,
      player: to_string(player),
      song: song,
      chart: chart,
      play_style: play_style
    )
  end

  @doc "The stats row for a chart, or nil."
  def get_stats(game, song, chart, play_style \\ "") do
    Repo.get_by(ScoreStat, game: game, song: song, chart: chart, play_style: play_style)
  end

  ## Stages

  defp insert_attempt!(event) do
    Repo.insert!(%PlayAttempt{
      game: event.game,
      version: event.version,
      player: to_string(event.player),
      song: event.song,
      chart: event.chart,
      play_style: event[:play_style] || "",
      score: event[:score],
      clear: event[:clear],
      miss: event[:miss],
      payload: event[:attempt] || %{}
    })
  end

  defp upsert_best!(event) do
    spec = event.merge

    sql = """
    INSERT INTO best_scores
      (game, player, song, chart, play_style, version, score, clear, miss, payload,
       inserted_at, updated_at)
    VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::text::jsonb, now(), now())
    ON CONFLICT (game, player, song, chart, play_style) DO UPDATE SET
      version = excluded.version,
      score = greatest(best_scores.score, excluded.score),
      clear = greatest(best_scores.clear, excluded.clear),
      miss = #{Merge.miss_sql(spec.miss)},
      payload = #{Merge.payload_sql(spec)},
      updated_at = now()
    RETURNING id, score, clear, miss, payload
    """

    params = [
      event.game,
      to_string(event.player),
      event.song,
      event.chart,
      event[:play_style] || "",
      event.version,
      event.score,
      event.clear,
      event[:miss],
      Jason.encode!(event.payload)
    ]

    %{rows: [[id, score, clear, miss, payload]]} = Repo.query!(sql, params)
    %{id: id, score: score, clear: clear, miss: miss, payload: payload}
  end

  defp bump_stats!(event) do
    sql = """
    INSERT INTO score_stats
      (game, song, chart, play_style, play_count, clear_count, fc_count, updated_at)
    VALUES ($1, $2, $3, $4, 1, $5, $6, now())
    ON CONFLICT (game, song, chart, play_style) DO UPDATE SET
      play_count = score_stats.play_count + 1,
      clear_count = score_stats.clear_count + excluded.clear_count,
      fc_count = score_stats.fc_count + excluded.fc_count,
      updated_at = now()
    RETURNING play_count, clear_count, fc_count
    """

    params = [
      event.game,
      event.song,
      event.chart,
      event[:play_style] || "",
      bool_int(event.stats.clear),
      bool_int(event.stats.fc)
    ]

    %{rows: [[play_count, clear_count, fc_count]]} = Repo.query!(sql, params)
    %{play_count: play_count, clear_count: clear_count, fc_count: fc_count}
  end

  defp append_outbox!(event, attempt) do
    Repo.insert!(%OutboxEvent{
      topic: "score.recorded",
      payload: %{
        "game" => event.game,
        "version" => event.version,
        "player" => to_string(event.player),
        "song" => event.song,
        "chart" => event.chart,
        "play_style" => event[:play_style] || "",
        "score" => event[:score],
        "clear" => event[:clear],
        "attempt_id" => attempt.id
      }
    })
  end

  defp recorded_response(recorded) do
    %{
      "attempt_id" => recorded.attempt_id,
      "best" => %{
        "score" => recorded.best.score,
        "clear" => recorded.best.clear,
        "miss" => recorded.best.miss,
        "payload" => recorded.best.payload
      },
      "stats" => %{
        "play_count" => recorded.stats.play_count,
        "clear_count" => recorded.stats.clear_count,
        "fc_count" => recorded.stats.fc_count
      },
      "extra" => recorded.extra
    }
  end

  defp bool_int(true), do: 1
  defp bool_int(_), do: 0
end
