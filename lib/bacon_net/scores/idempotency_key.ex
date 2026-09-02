defmodule BaconNet.Scores.IdempotencyKey do
  @moduledoc """
  Claimed idempotency keys. `response` holds the recorded outcome of the
  first committed submission; a replay of the same key and payload returns
  it without further effects.
  """

  use Ecto.Schema

  schema "idempotency_keys" do
    field(:key, :string)
    field(:scope, :string)
    field(:payload_hash, :string)
    field(:response, :map)
    field(:created_at, :utc_datetime_usec)
  end
end
