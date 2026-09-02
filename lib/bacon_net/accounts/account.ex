defmodule BaconNet.Accounts.Account do
  @moduledoc "A registered webui account (normalized replacement for webui_users docs)."

  use Ecto.Schema

  import Ecto.Changeset

  alias BaconNet.Accounts.{Card, Session}

  @username_regex ~r/^[a-z0-9_]{3,24}$/

  schema "accounts" do
    field(:username, :string)
    field(:display_name, :string)
    field(:pass_hash, :string)
    field(:salt, :string)
    field(:iterations, :integer)
    field(:banned, :boolean, default: false)
    field(:admin, :boolean, default: false)

    has_many(:sessions, Session)
    has_many(:cards, Card)

    timestamps(type: :utc_datetime_usec)
  end

  def username_regex, do: @username_regex

  def registration_changeset(account, attrs) do
    account
    |> cast(attrs, [:username, :display_name, :pass_hash, :salt, :iterations])
    |> validate_required([:username, :pass_hash, :salt, :iterations])
    |> validate_format(:username, @username_regex)
    |> validate_length(:display_name, max: 64)
    |> unique_constraint(:username,
      name: :accounts_username_lower_index,
      message: "has already been taken"
    )
  end

  def ban_changeset(account, banned) do
    change(account, banned: banned)
  end
end
