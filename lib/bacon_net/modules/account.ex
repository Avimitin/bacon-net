defmodule BaconNet.Modules.Account do
  @moduledoc """
  Player account API for the webui (register/login, card binding, own
  profiles/settings, own scores, server rankings).

  Accounts, sessions, and card bindings live in the normalized
  `accounts`/`account_sessions`/`account_cards` tables via
  `BaconNet.Accounts`; uniqueness and ownership are enforced by database
  constraints, so concurrent registrations and card binds cannot race.
  Authentication is `Authorization: Bearer <token>`; sessions store only
  the SHA-256 digest of the token.

  Game profiles and scores stay JSONB documents in the `documents` table
  (game-defined shapes), but every per-user lookup filters by the owner's
  bound cards / game ids with index-friendly predicates.

  Profile PATCH is restricted to an allowlist of editable top-level fields
  (`pin`, `version`) — a profile can never be reassigned to another card,
  and no credentials/identity fields can be written. Profile documents
  carry no version counter, so there is no etag/optimistic concurrency;
  the allowlist plus per-version-key merge is the guard.

  Score history and rankings are paginated: `{"items": [...],
  "next_cursor": ...}` with `limit` (default 50, max 200) and an opaque
  `cursor` param. Rankings additionally require `game`, `song`, and
  `chart` and compute a bounded top-N in SQL.
  """

  import Ecto.Query
  import Plug.Conn, only: [fetch_query_params: 1, get_req_header: 2, send_resp: 3]

  alias BaconNet.{Accounts, Api, Card, DB}
  alias BaconNet.Accounts.Account
  alias BaconNet.DB.Document
  alias BaconNet.Repo

  @max_password_bytes 1024
  @default_limit 50
  @max_limit 200

  # Editable top-level profile fields for PATCH. Never `_id`, `card`, the
  # game's id field, or anything credential-shaped; everything else the
  # games write is read-only through this API.
  @editable_profile_fields ["pin", "version"]

  # Game registry: how profiles and score tables link together per game.
  # `song_field`/`chart_field`/`score_field` describe score rows so the
  # frontend can render listings and rankings without game-specific code.
  @games [
    %{
      "key" => "iidx",
      "name" => "beatmania IIDX",
      "profile_table" => "iidx_profile",
      "id_field" => "iidx_id",
      "score_tables" => [
        %{
          "table" => "iidx_scores",
          "kind" => "history",
          "song_field" => "music_id",
          "chart_field" => "chart_id",
          "score_field" => "ex_score"
        },
        %{
          "table" => "iidx_scores_best",
          "kind" => "best",
          "song_field" => "music_id",
          "chart_field" => "chart_id",
          "score_field" => "ex_score"
        }
      ]
    },
    %{
      "key" => "ddr",
      "name" => "DanceDanceRevolution",
      "profile_table" => "ddr_profile",
      "id_field" => "ddr_id",
      "score_tables" => [
        %{
          "table" => "ddr_scores",
          "kind" => "history",
          "song_field" => "mcode",
          "chart_field" => "difficulty",
          "score_field" => "score"
        },
        %{
          "table" => "ddr_scores_best",
          "kind" => "best",
          "song_field" => "mcode",
          "chart_field" => "difficulty",
          "score_field" => "score"
        }
      ]
    },
    %{
      "key" => "sdvx",
      "name" => "SOUND VOLTEX",
      "profile_table" => "sdvx_profile",
      "id_field" => "sdvx_id",
      "score_tables" => [
        %{
          "table" => "sdvx_scores",
          "kind" => "history",
          "song_field" => "music_id",
          "chart_field" => "music_type",
          "score_field" => "score"
        },
        %{
          "table" => "sdvx_scores_best",
          "kind" => "best",
          "song_field" => "music_id",
          "chart_field" => "music_type",
          "score_field" => "score"
        }
      ]
    },
    %{
      "key" => "gitadora",
      "name" => "GITADORA",
      "profile_table" => "gitadora_profile",
      "id_field" => "gitadora_id",
      "score_tables" => [
        %{
          "table" => "drummania_scores",
          "kind" => "history",
          "song_field" => "musicid",
          "chart_field" => "seq",
          "score_field" => "perc"
        },
        %{
          "table" => "drummania_scores_best",
          "kind" => "best",
          "song_field" => "musicid",
          "chart_field" => "seq",
          "score_field" => "perc"
        },
        %{
          "table" => "guitarfreaks_scores",
          "kind" => "history",
          "song_field" => "musicid",
          "chart_field" => "seq",
          "score_field" => "perc"
        },
        %{
          "table" => "guitarfreaks_scores_best",
          "kind" => "best",
          "song_field" => "musicid",
          "chart_field" => "seq",
          "score_field" => "perc"
        }
      ]
    },
    %{
      "key" => "drs",
      "name" => "DANCERUSH STARDOM",
      "profile_table" => "dancerush_profile",
      "id_field" => "drs_id",
      "score_tables" => [
        %{
          "table" => "drs_scores",
          "kind" => "history",
          "song_field" => "music_id",
          "chart_field" => "music_type",
          "score_field" => "score"
        },
        %{
          "table" => "drs_scores_best",
          "kind" => "best",
          "song_field" => "music_id",
          "chart_field" => "music_type",
          "score_field" => "score"
        }
      ]
    },
    %{
      "key" => "nostalgia",
      "name" => "NOSTALGIA",
      "profile_table" => "nostalgia_profile",
      "id_field" => "nostalgia_id",
      "score_tables" => [
        %{
          "table" => "nostalgia_scores",
          "kind" => "history",
          "song_field" => "music_index",
          "chart_field" => "sheet_type",
          "score_field" => "score"
        },
        %{
          "table" => "nostalgia_scores_best",
          "kind" => "best",
          "song_field" => "music_index",
          "chart_field" => "sheet_type",
          "score_field" => "score"
        }
      ]
    }
  ]

  def games, do: @games

  def routes do
    %{
      prefix: "/account",
      tag: "api_account",
      handlers: [],
      api: [
        {:post, ["api", "register"], :account_register},
        {:post, ["api", "login"], :account_login},
        {:post, ["api", "logout"], :account_logout},
        {:get, ["api", "games"], :account_games},
        {:get, ["api", "me"], :account_me},
        {:post, ["api", "cards"], :account_card_bind},
        {:delete, ["api", "cards", :card], :account_card_unbind},
        {:get, ["api", "profiles"], :account_profiles},
        {:get, ["api", "profiles", :table, :id], :account_profile_get},
        {:patch, ["api", "profiles", :table, :id], :account_profile_patch},
        {:get, ["api", "scores"], :account_scores},
        {:get, ["api", "rankings"], :account_rankings}
      ]
    }
  end

  ## Auth endpoints

  def account_register(conn, _params) do
    with {:ok, body} <- body_object(conn),
         {:ok, username} <- valid_username(body["username"]),
         {:ok, password} <- valid_password(body["password"]) do
      case Accounts.register(username, password) do
        {:ok, _account, token, expires_at} ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> send_resp(201, Jason.encode!(session_response(token, expires_at, username)))

        {:error, :username_taken} ->
          Api.error(conn, 409, "username_taken")

        {:error, _other} ->
          Api.error(conn, 400, "invalid_body")
      end
    else
      {:error, reason} -> Api.error(conn, 400, reason)
      :error -> Api.error(conn, 400, "invalid_body")
    end
  end

  def account_login(conn, _params) do
    with {:ok, body} <- body_object(conn),
         username when is_binary(username) <- body["username"],
         password when is_binary(password) and byte_size(password) <= @max_password_bytes <-
           body["password"],
         %Account{} = account <- Accounts.get_by_username(username),
         {:ok, account} <- Accounts.verify_password(account, password) do
      if account.banned do
        Api.error(conn, 403, "account_banned")
      else
        Accounts.purge_expired_sessions()
        {token, expires_at} = Accounts.create_session(account)
        Api.json(conn, session_response(token, expires_at, account.username))
      end
    else
      _ -> Api.error(conn, 401, "invalid_credentials")
    end
  end

  def account_logout(conn, _params) do
    with_auth(conn, fn _account, digest ->
      Accounts.revoke_session(digest)
      send_resp(conn, 204, "")
    end)
  end

  def account_games(conn, _params) do
    Api.json(conn, %{"games" => @games})
  end

  def account_me(conn, _params) do
    with_auth(conn, fn account, _digest ->
      Api.json(conn, public_user(account))
    end)
  end

  ## Card binding

  def account_card_bind(conn, _params) do
    with_auth(conn, fn account, _digest ->
      with {:ok, body} <- body_object(conn),
           normalized when not is_nil(normalized) <- Card.normalize(body["card"] || "") do
        case Accounts.bind_card(account, normalized["uid"], normalized["konami_id"]) do
          {:ok, _card} ->
            Api.json(conn, %{
              "cards" => Accounts.list_card_uids(account.id),
              "bound" => normalized
            })

          {:error, :already_bound} ->
            Api.error(conn, 409, "card_already_bound")

          {:error, :bound_to_other} ->
            Api.error(conn, 409, "card_bound_to_other_account")

          {:error, _changeset} ->
            Api.error(conn, 400, "invalid_card")
        end
      else
        :error -> Api.error(conn, 400, "invalid_body")
        nil -> Api.error(conn, 400, "invalid_card")
      end
    end)
  end

  def account_card_unbind(conn, %{"card" => card}) do
    with_auth(conn, fn account, _digest ->
      uid = (Card.normalize(card) || %{}) |> Map.get("uid", String.upcase(card))

      case Accounts.unbind_card(account, uid) do
        :ok -> Api.json(conn, %{"cards" => Accounts.list_card_uids(account.id)})
        {:error, :not_found} -> Api.error(conn, 404, "not_found")
      end
    end)
  end

  ## Profiles (ownership-checked)

  def account_profiles(conn, _params) do
    with_auth(conn, fn account, _digest ->
      cards = Accounts.list_card_uids(account.id)

      profiles =
        for game <- @games,
            {doc_id, doc} <- docs_with_any_card(game["profile_table"], cards) do
          %{
            "game" => game["key"],
            "table" => game["profile_table"],
            "doc_id" => doc_id,
            "card" => doc["card"],
            "game_id" => doc[game["id_field"]],
            "name" => Api.profile_name(doc),
            "versions" => version_keys(doc),
            "pin" => doc["pin"]
          }
        end

      Api.json(conn, %{"profiles" => profiles})
    end)
  end

  def account_profile_get(conn, %{"table" => table, "id" => id}) do
    with_auth(conn, fn account, _digest ->
      with :ok <- known_profile_table(table),
           doc when not is_nil(doc) <- DB.get_by_id(table, id),
           true <- doc["card"] in Accounts.list_card_uids(account.id) do
        Api.json(conn, Map.put(doc, "_id", id))
      else
        _ -> Api.error(conn, 404, "not_found")
      end
    end)
  end

  def account_profile_patch(conn, %{"table" => table, "id" => id}) do
    with_auth(conn, fn account, _digest ->
      with :ok <- known_profile_table(table),
           doc when not is_nil(doc) <- DB.get_by_id(table, id),
           true <- doc["card"] in Accounts.list_card_uids(account.id),
           {:ok, fields} <- body_object(conn),
           {:ok, patch} <- profile_patch(doc, fields) do
        :ok = DB.update_by_id(table, id, patch)
        Api.json(conn, Map.put(DB.get_by_id(table, id), "_id", id))
      else
        :error -> Api.error(conn, 400, "invalid_body")
        {:error, reason} -> Api.error(conn, 400, reason)
        _ -> Api.error(conn, 404, "not_found")
      end
    end)
  end

  ## Scores (cursor-paginated)

  def account_scores(conn, _params) do
    conn = fetch_query_params(conn)

    with_auth(conn, fn account, _digest ->
      with {:ok, limit} <- parse_limit(conn.query_params["limit"]),
           {:ok, cursor} <- parse_cursor(conn.query_params["cursor"]) do
        clauses = score_clauses(Accounts.list_card_uids(account.id))
        {items, next_cursor} = fetch_scores_page(clauses, cursor, limit)
        Api.json(conn, %{"items" => items, "next_cursor" => next_cursor})
      else
        {:error, reason} -> Api.error(conn, 400, reason)
      end
    end)
  end

  def account_rankings(conn, _params) do
    conn = fetch_query_params(conn)

    with_auth(conn, fn _account, _digest ->
      with {:ok, game} <- fetch_game(conn.query_params["game"]),
           {:ok, song} <- parse_int_param(conn.query_params["song"]),
           {:ok, chart} <- parse_int_param(conn.query_params["chart"]),
           {:ok, limit} <- parse_limit(conn.query_params["limit"]) do
        st = Enum.find(game["score_tables"], &(&1["kind"] == "best"))
        rows = top_scores(st, song, chart, limit)
        names = name_map(game, Enum.map(rows, & &1[game["id_field"]]))

        items =
          rows
          |> Enum.with_index(1)
          |> Enum.map(fn {row, rank} ->
            game_id = row[game["id_field"]]

            %{
              "song" => row[st["song_field"]],
              "chart" => row[st["chart_field"]],
              "rank" => rank,
              "game_id" => game_id,
              "name" => Map.get(names, game_id),
              "score" => score_of(row, st),
              "timestamp" => row["timestamp"]
            }
          end)

        Api.json(conn, %{
          "game" => game["key"],
          "table" => st["table"],
          "song" => song,
          "chart" => chart,
          "items" => items
        })
      else
        {:error, reason} -> Api.error(conn, 400, reason)
      end
    end)
  end

  ## Input validation

  defp valid_username(nil), do: {:error, "invalid_username"}

  defp valid_username(username) when is_binary(username) do
    username = String.downcase(username)

    if username =~ Account.username_regex() do
      {:ok, username}
    else
      {:error, "invalid_username"}
    end
  end

  defp valid_password(pw) when is_binary(pw) and byte_size(pw) > @max_password_bytes,
    do: {:error, "password_too_long"}

  defp valid_password(pw) when is_binary(pw) and byte_size(pw) >= 8, do: {:ok, pw}
  defp valid_password(_), do: {:error, "password_too_short"}

  # Profile PATCH allowlist: only `pin` (4-digit string) and `version`
  # (map of numeric version key => map of scalar settings) may be written.
  # `version` merges per version key so a patch cannot wipe other versions.
  defp profile_patch(_doc, fields) when map_size(fields) == 0, do: {:error, "empty_patch"}

  defp profile_patch(doc, fields) do
    unknown = Map.keys(fields) -- @editable_profile_fields

    if unknown != [] do
      {:error, "field_not_editable"}
    else
      with {:ok, pin} <- patch_pin(fields),
           {:ok, version} <- patch_version(doc, fields) do
        {:ok, Map.merge(pin, version)}
      end
    end
  end

  defp patch_pin(%{"pin" => pin}) when is_binary(pin) do
    if pin =~ ~r/^\d{4}$/, do: {:ok, %{"pin" => pin}}, else: {:error, "invalid_pin"}
  end

  defp patch_pin(%{"pin" => _}), do: {:error, "invalid_pin"}
  defp patch_pin(_), do: {:ok, %{}}

  defp patch_version(doc, %{"version" => version}) when is_map(version) do
    valid =
      Enum.all?(version, fn {key, value} ->
        is_binary(key) and key =~ ~r/^\d+$/ and is_map(value) and
          Enum.all?(value, fn {_k, v} -> scalar?(v) end)
      end)

    if valid do
      merged = Map.merge(doc["version"] || %{}, version)
      {:ok, %{"version" => merged}}
    else
      {:error, "invalid_version"}
    end
  end

  defp patch_version(_doc, %{"version" => _}), do: {:error, "invalid_version"}
  defp patch_version(_doc, _fields), do: {:ok, %{}}

  defp scalar?(v) when is_binary(v) or is_number(v) or is_boolean(v) or is_nil(v), do: true
  defp scalar?(v) when is_list(v), do: Enum.all?(v, &scalar?/1)
  defp scalar?(_), do: false

  ## Pagination

  defp parse_limit(nil), do: {:ok, @default_limit}

  defp parse_limit(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {n, ""} when n >= 1 -> {:ok, min(n, @max_limit)}
      _ -> {:error, "invalid_limit"}
    end
  end

  defp parse_limit(_), do: {:error, "invalid_limit"}

  defp parse_cursor(nil), do: {:ok, nil}

  defp parse_cursor(raw) when is_binary(raw) do
    with {:ok, decoded} <- Base.url_decode64(raw, padding: false),
         {:ok, seq} <- Jason.decode(decoded),
         true <- is_integer(seq) do
      {:ok, seq}
    else
      _ -> {:error, "invalid_cursor"}
    end
  end

  defp parse_cursor(_), do: {:error, "invalid_cursor"}

  defp encode_cursor(seq), do: seq |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp parse_int_param(nil), do: {:error, "missing_parameters"}

  defp parse_int_param(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {n, ""} -> {:ok, n}
      _ -> {:error, "invalid_parameters"}
    end
  end

  defp parse_int_param(_), do: {:error, "invalid_parameters"}

  defp fetch_game(nil), do: {:error, "missing_parameters"}

  defp fetch_game(key) do
    case Enum.find(@games, &(&1["key"] == key)) do
      nil -> {:error, "unknown_game"}
      game -> {:ok, game}
    end
  end

  ## Document queries (index-friendly: containment matches the GIN index)

  # Profile docs owned by any of the account's cards. `data @> {"card": uid}`
  # is exact for scalar values and can use the documents GIN index.
  defp docs_with_any_card(_table, []), do: []

  defp docs_with_any_card(table, cards) do
    any_card =
      Enum.reduce(cards, false, fn uid, acc ->
        dynamic(
          [d],
          ^acc or fragment("? @> ?::text::jsonb", d.data, ^Jason.encode!(%{"card" => uid}))
        )
      end)

    filter = dynamic([d], d.table_name == ^table and ^any_card)

    Repo.all(
      from(d in Document,
        where: ^filter,
        order_by: [asc: d.seq],
        select: {d.doc_id, d.data}
      )
    )
  end

  defp my_game_ids(game, cards) do
    game["profile_table"]
    |> docs_with_any_card(cards)
    |> Enum.map(fn {_id, doc} -> doc[game["id_field"]] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  # One {score_table, game, game_ids} clause per score table the account has
  # profiles for.
  defp score_clauses(cards) do
    for game <- @games,
        ids = my_game_ids(game, cards),
        ids != [],
        st <- game["score_tables"] do
      {st, game, ids}
    end
  end

  defp fetch_scores_page([], _cursor, _limit), do: {[], nil}

  defp fetch_scores_page(clauses, cursor, limit) do
    cond =
      Enum.reduce(clauses, false, fn {st, game, ids}, acc ->
        id_strings = Enum.map(ids, &to_string/1)

        dynamic(
          [d],
          ^acc or
            (d.table_name == ^st["table"] and
               fragment("(?->>?) = ANY(?)", d.data, ^game["id_field"], ^id_strings))
        )
      end)

    query =
      from(d in Document,
        where: ^cond,
        order_by: [asc: d.seq],
        limit: ^(limit + 1),
        select: {d.seq, d.table_name, d.data}
      )

    query = if cursor, do: from(d in query, where: d.seq > ^cursor), else: query

    rows = Repo.all(query)
    {page, rest} = Enum.split(rows, limit)

    next_cursor =
      case {page, rest} do
        {[], _} -> nil
        {_, []} -> nil
        _ -> page |> List.last() |> elem(0) |> encode_cursor()
      end

    table_game = Map.new(clauses, fn {st, game, _ids} -> {st["table"], game["key"]} end)

    items =
      Enum.map(page, fn {_seq, table, data} ->
        data
        |> Map.put("game", table_game[table])
        |> Map.put("table", table)
      end)

    {items, next_cursor}
  end

  # Bounded top-N for one song+chart, computed in SQL: filter, order by the
  # numeric score descending, limit. Ties keep insertion order (seq).
  defp top_scores(st, song, chart, limit) do
    score_field = st["score_field"]

    Repo.all(
      from(d in Document,
        where:
          d.table_name == ^st["table"] and
            fragment("?->>?", d.data, ^st["song_field"]) == ^to_string(song) and
            fragment("?->>?", d.data, ^st["chart_field"]) == ^to_string(chart),
        order_by: [
          desc:
            fragment(
              "CASE WHEN jsonb_typeof(?->?) = 'number' THEN (?->>?)::numeric ELSE 0 END",
              d.data,
              ^score_field,
              d.data,
              ^score_field
            ),
          asc: d.seq
        ],
        limit: ^limit,
        select: d.data
      )
    )
  end

  defp name_map(_game, []), do: %{}

  defp name_map(game, game_ids) do
    id_strings = game_ids |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.map(&to_string/1)

    Repo.all(
      from(d in Document,
        where:
          d.table_name == ^game["profile_table"] and
            fragment("(?->>?) = ANY(?)", d.data, ^game["id_field"], ^id_strings),
        select: d.data
      )
    )
    |> Map.new(fn doc -> {doc[game["id_field"]], Api.profile_name(doc)} end)
  end

  ## Auth plumbing

  defp with_auth(conn, fun) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, account, digest} <- Accounts.authenticate_token(token) do
      fun.(account, digest)
    else
      _ -> Api.error(conn, 401, "unauthorized")
    end
  end

  defp session_response(token, expires_at, username) do
    %{"token" => token, "expires_at" => expires_at, "username" => username}
  end

  defp public_user(account) do
    %{
      "username" => account.username,
      "display_name" => account.display_name,
      "cards" => Accounts.list_card_uids(account.id),
      "created_at" => DateTime.to_unix(account.inserted_at)
    }
  end

  defp body_object(conn) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} -> :error
      params when is_map(params) -> {:ok, params}
      _ -> :error
    end
  end

  defp known_profile_table(table) do
    if Enum.any?(@games, &(&1["profile_table"] == table)), do: :ok, else: :unknown
  end

  defp version_keys(%{"version" => versions}) when is_map(versions) do
    versions
    |> Map.keys()
    |> Enum.sort_by(fn k ->
      case Integer.parse(k) do
        {n, _} -> n
        :error -> 0
      end
    end)
  end

  defp version_keys(_), do: []

  defp score_of(row, st) do
    case row[st["score_field"]] do
      n when is_number(n) -> n
      _ -> 0
    end
  end
end
