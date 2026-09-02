defmodule BaconNet.Scores.ScoreStat do
  @moduledoc """
  Per-(game, song, chart, play_style) counters, bumped atomically with
  `SET x = x + 1` upserts so concurrent submissions never lose increments.
  """

  use Ecto.Schema

  schema "score_stats" do
    field(:game, :string)
    field(:song, :integer)
    field(:chart, :integer)
    field(:play_style, :string, default: "")
    field(:play_count, :integer)
    field(:clear_count, :integer)
    field(:fc_count, :integer)
    field(:updated_at, :utc_datetime_usec)
  end
end
