defmodule BaconNet.Accounts.Card do
  @moduledoc """
  An e-amusement card bound to an account. The unique index on `card_uid`
  makes a card owned by exactly one account at a time.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias BaconNet.Accounts.Account

  schema "account_cards" do
    field(:card_uid, :string)
    field(:konami_id, :string)

    belongs_to(:account, Account)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(card, attrs) do
    card
    |> cast(attrs, [:account_id, :card_uid, :konami_id])
    |> validate_required([:account_id, :card_uid])
    |> validate_format(:card_uid, ~r/^[0-9A-F]{16}$/)
    |> unique_constraint(:card_uid, message: "already bound")
    |> foreign_key_constraint(:account_id)
  end
end
