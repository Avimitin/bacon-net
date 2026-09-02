defmodule BaconNet.Accounts do
  @moduledoc """
  Accounts context: registration, authentication, sessions, and card
  binding over the normalized `accounts` / `account_sessions` /
  `account_cards` tables.

  Invariants are enforced by the database, not by check-then-act:
  `accounts.username` is unique case-insensitively (unique index on
  `lower(username)`), session token digests are unique, and a card UID has
  exactly one owner (unique index on `account_cards.card_uid`). Concurrent
  callers that would race simply lose on the constraint and get a
  deterministic conflict error.

  Password hashing keeps the PBKDF2-SHA256 format used by the previous
  document store (`pass_hash`/`salt`/`iterations`, hex-encoded), and
  sessions store only the SHA-256 hex digest of the bearer token.
  """

  import Ecto.Query

  alias BaconNet.Accounts.{Account, Card, Session}
  alias BaconNet.Repo

  @pbkdf2_iterations 200_000
  @default_session_ttl_seconds 30 * 24 * 3600

  def pbkdf2_iterations, do: @pbkdf2_iterations

  defp session_ttl_seconds do
    Application.get_env(:bacon_net, :account_session_ttl_seconds, @default_session_ttl_seconds)
  end

  ## Registration / login

  @doc """
  Create an account and its initial session in one transaction: either
  both exist or nothing does.

  Returns `{:ok, account, token, expires_at}`, `{:error, :username_taken}`
  on a case-insensitive username conflict, or `{:error, changeset}` on
  validation failure.

  Options:
    * `:display_name` — optional display name.
    * `:before_commit` — test seam: a `fn account, session -> :ok | {:error, reason} end`
      invoked inside the transaction after both inserts; returning an error
      (or raising) rolls everything back.
  """
  def register(username, password, opts \\ []) do
    salt = :crypto.strong_rand_bytes(16)

    attrs = %{
      username: username,
      display_name: Keyword.get(opts, :display_name),
      pass_hash: hash_password(password, salt),
      salt: Base.encode16(salt),
      iterations: @pbkdf2_iterations
    }

    before_commit = Keyword.get(opts, :before_commit, fn _account, _session -> :ok end)

    Repo.transaction(fn ->
      account =
        case %Account{} |> Account.registration_changeset(attrs) |> Repo.insert() do
          {:ok, account} ->
            account

          {:error, %Ecto.Changeset{} = changeset} ->
            if unique_username_violation?(changeset) do
              Repo.rollback(:username_taken)
            else
              Repo.rollback({:invalid_account, changeset})
            end
        end

      {token, expires_at, session} = insert_session!(account)

      case before_commit.(account, session) do
        :ok -> {account, token, expires_at}
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, {account, token, expires_at}} -> {:ok, account, token, expires_at}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Case-insensitive username lookup."
  def get_by_username(username) when is_binary(username) do
    Repo.one(
      from(a in Account,
        where: fragment("lower(?)", a.username) == ^String.downcase(username)
      )
    )
  end

  @doc """
  Verify a password against an account using constant-time comparison.
  Returns {:ok, account} or :error.
  """
  def verify_password(%Account{} = account, password) when is_binary(password) do
    salt = Base.decode16!(account.salt)
    hash = hash_password(password, salt, account.iterations || @pbkdf2_iterations)
    if Plug.Crypto.secure_compare(hash, account.pass_hash), do: {:ok, account}, else: :error
  end

  @doc "Create a session for an account. Returns {token, expires_at}."
  def create_session(%Account{} = account) do
    {token, expires_at, _session} = insert_session!(account)
    {token, expires_at}
  end

  ## Sessions

  @doc """
  Authenticate a bearer token. Returns {:ok, account, digest} or :error
  (unknown, expired, or revoked token, or banned account). Updates the
  session's last_used_at on success.
  """
  def authenticate_token(token) when is_binary(token) do
    digest = hash_token(token)
    now = System.system_time(:second)

    case Repo.one(from(s in Session, where: s.token_digest == ^digest, preload: [:account])) do
      nil ->
        :error

      %Session{revoked: true} ->
        :error

      %Session{expires_at: expires_at} when expires_at <= now ->
        :error

      %Session{account: %Account{banned: true}} ->
        :error

      %Session{} = session ->
        touch_session(session.id, now)
        {:ok, session.account, digest}
    end
  end

  @doc "Revoke the session with the given token digest. Idempotent."
  def revoke_session(digest) when is_binary(digest) do
    Repo.update_all(
      from(s in Session, where: s.token_digest == ^digest),
      set: [revoked: true]
    )

    :ok
  end

  @doc "Delete all expired sessions."
  def purge_expired_sessions do
    now = System.system_time(:second)
    Repo.delete_all(from(s in Session, where: s.expires_at <= ^now))
    :ok
  end

  ## Cards

  @doc """
  Bind a card to an account, relying on the unique index on `card_uid`.
  Returns {:ok, card}, {:error, :already_bound} (same account),
  {:error, :bound_to_other} (different account), or {:error, changeset}.
  """
  def bind_card(%Account{} = account, card_uid, konami_id \\ nil) do
    %Card{}
    |> Card.changeset(%{account_id: account.id, card_uid: card_uid, konami_id: konami_id})
    |> Repo.insert()
    |> case do
      {:ok, card} ->
        {:ok, card}

      {:error, %Ecto.Changeset{} = changeset} ->
        if unique_card_violation?(changeset) do
          case Repo.get_by(Card, card_uid: card_uid) do
            %Card{account_id: id} when id == account.id -> {:error, :already_bound}
            %Card{} -> {:error, :bound_to_other}
            nil -> {:error, changeset}
          end
        else
          {:error, changeset}
        end
    end
  end

  @doc "Unbind a card from an account. Returns :ok or {:error, :not_found}."
  def unbind_card(%Account{} = account, card_uid) do
    {count, _} =
      Repo.delete_all(
        from(c in Card, where: c.account_id == ^account.id and c.card_uid == ^card_uid)
      )

    if count == 0, do: {:error, :not_found}, else: :ok
  end

  @doc "Card UIDs bound to an account, oldest first."
  def list_card_uids(account_id) do
    Repo.all(from(c in Card, where: c.account_id == ^account_id, order_by: [asc: c.id]))
    |> Enum.map(& &1.card_uid)
  end

  @doc "Bound card with the given UID, or nil."
  def get_card(card_uid), do: Repo.get_by(Card, card_uid: card_uid)

  ## Admin-ish helpers

  @doc "Set or clear the banned flag."
  def set_banned(%Account{} = account, banned) do
    account |> Account.ban_changeset(banned) |> Repo.update!()
  end

  ## Hashing (format kept from the document-store era)

  def hash_password(password, salt, iterations \\ @pbkdf2_iterations) do
    :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, 32)
    |> Base.encode16()
  end

  def hash_token(token), do: :crypto.hash(:sha256, token) |> Base.encode16()

  ## Internals

  defp insert_session!(%Account{} = account) do
    token = :crypto.strong_rand_bytes(32) |> Base.hex_encode32(case: :lower, padding: false)
    now = System.system_time(:second)
    expires_at = now + session_ttl_seconds()

    session =
      %Session{}
      |> Session.changeset(%{
        account_id: account.id,
        token_digest: hash_token(token),
        last_used_at: now,
        expires_at: expires_at
      })
      |> Repo.insert!()

    {token, expires_at, session}
  end

  defp touch_session(session_id, now) do
    Repo.update_all(
      from(s in Session, where: s.id == ^session_id),
      set: [last_used_at: now]
    )
  end

  defp unique_username_violation?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:username, {_msg, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end

  defp unique_card_violation?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:card_uid, {_msg, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end
end
