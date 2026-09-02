defmodule BaconNet.Scores.BestScore do
  @moduledoc """
  Per-(game, player, song, chart, play_style) best score.

  `score`/`clear` only ever improve (SQL `greatest`); `miss` follows the
  game's merge rule; `payload` holds game-specific fields merged per the
  game's `BaconNet.Scores.Merge` spec.
  """

  use Ecto.Schema

  schema "best_scores" do
    field(:game, :string)
    field(:player, :string)
    field(:song, :integer)
    field(:chart, :integer)
    field(:play_style, :string, default: "")
    field(:version, :integer)
    field(:score, :integer)
    field(:clear, :integer)
    field(:miss, :integer)
    field(:payload, :map)
    field(:inserted_at, :utc_datetime_usec)
    field(:updated_at, :utc_datetime_usec)
  end
end
