defmodule BaconNet.Audit.Event do
  @moduledoc "One audit trail entry: who did what to what, and how it ended."
  use Ecto.Schema

  import Ecto.Changeset

  schema "audit_events" do
    field(:actor, :string)
    field(:action, :string)
    field(:target, :string)
    field(:outcome, :string)
    field(:request_id, :string)
    field(:metadata, :map)
    field(:created_at, :utc_datetime_usec)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:actor, :action, :target, :outcome, :request_id, :metadata])
    |> validate_required([:actor, :action, :outcome])
  end
end

defmodule BaconNet.Audit do
  @moduledoc """
  Append-only audit trail for administrative mutations.

  Events are written synchronously (the database is the acknowledgement
  boundary) but a failure to record is logged rather than failing the admin
  operation that triggered it.
  """

  require Logger

  import Ecto.Query

  alias BaconNet.Audit.Event
  alias BaconNet.Repo

  @max_limit 200

  @doc """
  Record an audit event. Attrs: actor, action, target, outcome, request_id,
  metadata. Returns {:ok, event} or {:error, reason} (logged).
  """
  def record(attrs) when is_map(attrs) do
    attrs
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> then(&Event.changeset(%Event{}, &1))
    |> Repo.insert()
    |> case do
      {:ok, event} ->
        {:ok, event}

      {:error, changeset} ->
        Logger.error("failed to record audit event #{inspect(attrs)}: #{inspect(changeset)}")
        {:error, changeset}
    end
  end

  @doc """
  List events newest first, paginated by id cursor. Options: :limit
  (clamped to #{@max_limit}), :cursor (only events with id < cursor).
  Returns {events, next_cursor}; next_cursor is nil when the page is short.
  """
  def list(opts \\ []) do
    limit = opts |> Keyword.get(:limit, 50) |> clamp_limit()
    cursor = Keyword.get(opts, :cursor)

    query =
      Event
      |> order_by([e], desc: e.id)
      |> limit(^limit)
      |> then(fn q -> if cursor, do: where(q, [e], e.id < ^cursor), else: q end)

    events = Repo.all(query)

    next_cursor =
      if length(events) == limit, do: List.last(events).id, else: nil

    {events, next_cursor}
  end

  @doc "Largest accepted page size."
  def max_limit, do: @max_limit

  defp clamp_limit(n) when is_integer(n) and n > 0, do: min(n, @max_limit)
  defp clamp_limit(_), do: 50
end
