defmodule BaconNet.Accounts.Session do
  @moduledoc """
  A bearer-token session. Only the SHA-256 hex digest of the token is
  stored; the plaintext token exists only in the register/login response.
  `last_used_at`/`expires_at` are unix seconds.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias BaconNet.Accounts.Account

  schema "account_sessions" do
    field(:token_digest, :string)
    field(:last_used_at, :integer)
    field(:expires_at, :integer)
    field(:revoked, :boolean, default: false)

    belongs_to(:account, Account)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:account_id, :token_digest, :last_used_at, :expires_at, :revoked])
    |> validate_required([:account_id, :token_digest, :last_used_at, :expires_at])
    |> unique_constraint(:token_digest)
    |> foreign_key_constraint(:account_id)
  end
end
