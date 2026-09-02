defmodule BaconNet.Scores.PlayAttempt do
  @moduledoc "Immutable record of a single play. One row per recorded attempt."

  use Ecto.Schema

  schema "play_attempts" do
    field(:game, :string)
    field(:version, :integer)
    field(:player, :string)
    field(:song, :integer)
    field(:chart, :integer)
    field(:play_style, :string, default: "")
    field(:score, :integer)
    field(:clear, :integer)
    field(:miss, :integer)
    field(:payload, :map)
    field(:created_at, :utc_datetime_usec)
  end
end
