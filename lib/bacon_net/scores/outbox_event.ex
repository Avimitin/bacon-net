defmodule BaconNet.Scores.OutboxEvent do
  @moduledoc """
  Transactional outbox. One event is appended in the same transaction as
  the score write; `published_at` is null while pending. Consumers are out
  of scope; the table plus appends are the contract.
  """

  use Ecto.Schema

  schema "outbox_events" do
    field(:topic, :string)
    field(:payload, :map)
    field(:created_at, :utc_datetime_usec)
    field(:published_at, :utc_datetime_usec)
  end
end
