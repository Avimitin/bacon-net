defmodule BaconNet.DB.Document do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  schema "documents" do
    field :table_name, :string
    field :doc_id, :string
    field :seq, :integer
    field :data, :map
    field :inserted_at, :utc_datetime_usec
  end
end
