defmodule BaconNet.Modules.Account do
  @moduledoc """
  Player account API for the webui (register/login, card binding, own
  profiles/settings, own scores, server rankings).

  Accounts and sessions are stored in the regular DB (`webui_users`,
  `webui_sessions` tables). Authentication is `Authorization: Bearer <token>`.
  Every profile/score access is checked against the cards bound to the
  account, and profile patches can never reassign a profile's `card`.
  """

  import Plug.Conn, only: [get_req_header: 2, send_resp: 3]

  alias BaconNet.{Api, Card, DB}

  @users_table "webui_users"
  @sessions_table "webui_sessions"
  @session_ttl_seconds 30 * 24 * 3600
  @pbkdf2_iterations 200_000
  @ranking_top 10

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
        %{"table" => "iidx_scores", "kind" => "history", "song_field" => "music_id", "chart_field" => "chart_id", "score_field" => "ex_score"},
        %{"table" => "iidx_scores_best", "kind" => "best", "song_field" => "music_id", "chart_field" => "chart_id", "score_field" => "ex_score"}
      ]
    },
    %{
      "key" => "ddr",
      "name" => "DanceDanceRevolution",
      "profile_table" => "ddr_profile",
      "id_field" => "ddr_id",
      "score_tables" => [
        %{"table" => "ddr_scores", "kind" => "history", "song_field" => "mcode", "chart_field" => "difficulty", "score_field" => "score"},
        %{"table" => "ddr_scores_best", "kind" => "best", "song_field" => "mcode", "chart_field" => "difficulty", "score_field" => "score"}
      ]
    },
    %{
      "key" => "sdvx",
      "name" => "SOUND VOLTEX",
      "profile_table" => "sdvx_profile",
      "id_field" => "sdvx_id",
      "score_tables" => [
        %{"table" => "sdvx_scores", "kind" => "history", "song_field" => "music_id", "chart_field" => "music_type", "score_field" => "score"},
        %{"table" => "sdvx_scores_best", "kind" => "best", "song_field" => "music_id", "chart_field" => "music_type", "score_field" => "score"}
      ]
    },
    %{
      "key" => "gitadora",
      "name" => "GITADORA",
      "profile_table" => "gitadora_profile",
      "id_field" => "gitadora_id",
      "score_tables" => [
        %{"table" => "drummania_scores", "kind" => "history", "song_field" => "musicid", "chart_field" => "seq", "score_field" => "perc"},
        %{"table" => "drummania_scores_best", "kind" => "best", "song_field" => "musicid", "chart_field" => "seq", "score_field" => "perc"},
        %{"table" => "guitarfreaks_scores", "kind" => "history", "song_field" => "musicid", "chart_field" => "seq", "score_field" => "perc"},
        %{"table" => "guitarfreaks_scores_best", "kind" => "best", "song_field" => "musicid", "chart_field" => "seq", "score_field" => "perc"}
      ]
    },
    %{
      "key" => "drs",
      "name" => "DANCERUSH STARDOM",
      "profile_table" => "dancerush_profile",
      "id_field" => "drs_id",
      "score_tables" => [
        %{"table" => "drs_scores", "kind" => "history", "song_field" => "music_id", "chart_field" => "music_type", "score_field" => "score"},
        %{"table" => "drs_scores_best", "kind" => "best", "song_field" => "music_id", "chart_field" => "music_type", "score_field" => "score"}
      ]
    },
    %{
      "key" => "nostalgia",
      "name" => "NOSTALGIA",
      "profile_table" => "nostalgia_profile",
      "id_field" => "nostalgia_id",
      "score_tables" => [
        %{"table" => "nostalgia_scores", "kind" => "history", "song_field" => "music_index", "chart_field" => "sheet_type", "score_field" => "score"},
        %{"table" => "nostalgia_scores_best", "kind" => "best", "song_field" => "music_index", "chart_field" => "sheet_type", "score_field" => "score"}
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
         {:ok, password} <- valid_password(body["password"]),
         :available <- username_available(username) do
      salt = :crypto.strong_rand_bytes(16)

      user = %{
        "username" => username,
        "pass_hash" => hash_password(password, salt),
        "salt" => Base.encode16(salt),
        "iterations" => @pbkdf2_iterations,
        "cards" => [],
        "created_at" => System.system_time(:second)
      }

      DB.insert(@users_table, user)
      {token, expires_at} = create_session(username)

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> send_resp(201, Jason.encode!(session_response(token, expires_at, username)))
    else
      {:error, reason} -> Api.error(conn, 400, reason)
      :taken -> Api.error(conn, 409, "username_taken")
      :error -> Api.error(conn, 400, "invalid_body")
    end
  end

  def account_login(conn, _params) do
    with {:ok, body} <- body_object(conn),
         username when is_binary(username) <- body["username"],
         password when is_binary(password) <- body["password"],
         user when not is_nil(user) <- DB.get(@users_table, %{"username" => String.downcase(username)}),
         true <- verify_password(user, password) do
      purge_expired_sessions()
      {token, expires_at} = create_session(user["username"])
      Api.json(conn, session_response(token, expires_at, user["username"]))
    else
      _ -> Api.error(conn, 401, "invalid_credentials")
    end
  end

  def account_logout(conn, _params) do
    with_auth(conn, fn _user, token ->
      DB.remove(@sessions_table, %{"token" => token})
      send_resp(conn, 204, "")
    end)
  end

  def account_games(conn, _params) do
    Api.json(conn, %{"games" => @games})
  end

  def account_me(conn, _params) do
    with_auth(conn, fn user, _token ->
      Api.json(conn, public_user(user))
    end)
  end

  ## Card binding

  def account_card_bind(conn, _params) do
    with_auth(conn, fn user, _token ->
      with {:ok, body} <- body_object(conn),
           normalized when not is_nil(normalized) <- Card.normalize(body["card"] || "") do
        uid = normalized["uid"]

        cond do
          uid in user["cards"] ->
            Api.error(conn, 409, "card_already_bound")

          bound_to_other?(uid, user["username"]) ->
            Api.error(conn, 409, "card_bound_to_other_account")

          true ->
            cards = user["cards"] ++ [uid]
            DB.update(@users_table, %{"cards" => cards}, %{"username" => user["username"]})
            Api.json(conn, %{"cards" => cards, "bound" => normalized})
        end
      else
        :error -> Api.error(conn, 400, "invalid_body")
        nil -> Api.error(conn, 400, "invalid_card")
      end
    end)
  end

  def account_card_unbind(conn, %{"card" => card}) do
    with_auth(conn, fn user, _token ->
      uid = (Card.normalize(card) || %{}) |> Map.get("uid", String.upcase(card))

      if uid in user["cards"] do
        cards = List.delete(user["cards"], uid)
        DB.update(@users_table, %{"cards" => cards}, %{"username" => user["username"]})
        Api.json(conn, %{"cards" => cards})
      else
        Api.error(conn, 404, "not_found")
      end
    end)
  end

  ## Profiles (ownership-checked)

  def account_profiles(conn, _params) do
    with_auth(conn, fn user, _token ->
      profiles =
        for game <- @games,
            {doc_id, doc} <- DB.all_with_ids(game["profile_table"]),
            doc["card"] in user["cards"] do
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
    with_auth(conn, fn user, _token ->
      with :ok <- known_profile_table(table),
           doc when not is_nil(doc) <- DB.get_by_id(table, id),
           true <- doc["card"] in user["cards"] do
        Api.json(conn, Map.put(doc, "_id", id))
      else
        _ -> Api.error(conn, 404, "not_found")
      end
    end)
  end

  def account_profile_patch(conn, %{"table" => table, "id" => id}) do
    with_auth(conn, fn user, _token ->
      with :ok <- known_profile_table(table),
           doc when not is_nil(doc) <- DB.get_by_id(table, id),
           true <- doc["card"] in user["cards"],
           {:ok, fields} <- body_object(conn) do
        # `card` is stripped so a profile can never be reassigned to a
        # different card through this endpoint.
        fields = fields |> Map.delete("_id") |> Map.delete("card")
        :ok = DB.update_by_id(table, id, fields)
        Api.json(conn, Map.put(DB.get_by_id(table, id), "_id", id))
      else
        :error -> Api.error(conn, 400, "invalid_body")
        _ -> Api.error(conn, 404, "not_found")
      end
    end)
  end

  ## Scores

  def account_scores(conn, _params) do
    with_auth(conn, fn user, _token ->
      games =
        for game <- @games, ids = my_game_ids(game, user["cards"]), ids != [] do
          tables =
            Map.new(game["score_tables"], fn st ->
              docs =
                ids
                |> Enum.flat_map(&DB.search(st["table"], %{game["id_field"] => &1}))
                |> Enum.sort_by(fn d -> {d[st["song_field"]] || 0, d[st["chart_field"]] || 0} end)

              {st["table"], docs}
            end)

          %{"game" => game["key"], "ids" => ids, "tables" => tables}
        end

      Api.json(conn, %{"games" => games})
    end)
  end

  def account_rankings(conn, _params) do
    with_auth(conn, fn _user, _token ->
      games =
        for game <- @games, st <- game["score_tables"], st["kind"] == "best" do
          names = name_map(game)

          entries =
            st["table"]
            |> DB.all()
            |> Enum.group_by(fn d -> {d[st["song_field"]], d[st["chart_field"]]} end)
            |> Enum.flat_map(fn {{song, chart}, rows} ->
              rows
              |> Enum.sort_by(&score_of(&1, st), &>=/2)
              |> Enum.take(@ranking_top)
              |> Enum.with_index(1)
              |> Enum.map(fn {row, rank} ->
                game_id = row[game["id_field"]]

                %{
                  "song" => song,
                  "chart" => chart,
                  "rank" => rank,
                  "game_id" => game_id,
                  "name" => Map.get(names, game_id),
                  "score" => score_of(row, st),
                  "timestamp" => row["timestamp"]
                }
              end)
            end)
            |> Enum.sort_by(fn e -> {e["song"] || 0, e["chart"] || 0, e["rank"]} end)

          if entries == [] do
            nil
          else
            %{"game" => game["key"], "table" => st["table"], "entries" => entries}
          end
        end
        |> Enum.reject(&is_nil/1)

      Api.json(conn, %{"games" => games})
    end)
  end

  ## Internals

  defp valid_username(nil), do: {:error, "invalid_username"}

  defp valid_username(username) when is_binary(username) do
    username = String.downcase(username)

    if username =~ ~r/^[a-z0-9_]{3,24}$/ do
      {:ok, username}
    else
      {:error, "invalid_username"}
    end
  end

  defp valid_password(pw) when is_binary(pw) and byte_size(pw) >= 8, do: {:ok, pw}
  defp valid_password(_), do: {:error, "password_too_short"}

  defp username_available(username) do
    if DB.get(@users_table, %{"username" => username}), do: :taken, else: :available
  end

  defp hash_password(password, salt) do
    :crypto.pbkdf2_hmac(:sha256, password, salt, @pbkdf2_iterations, 32)
    |> Base.encode16()
  end

  defp verify_password(user, password) do
    salt = Base.decode16!(user["salt"])
    hash = hash_password(password, salt)
    Plug.Crypto.secure_compare(hash, user["pass_hash"])
  end

  defp create_session(username) do
    token = :crypto.strong_rand_bytes(32) |> Base.hex_encode32(case: :lower, padding: false)
    expires_at = System.system_time(:second) + @session_ttl_seconds
    DB.insert(@sessions_table, %{"token" => token, "username" => username, "expires_at" => expires_at})
    {token, expires_at}
  end

  defp session_response(token, expires_at, username) do
    %{"token" => token, "expires_at" => expires_at, "username" => username}
  end

  defp purge_expired_sessions do
    now = System.system_time(:second)

    for {id, session} <- DB.all_with_ids(@sessions_table),
        (session["expires_at"] || 0) <= now do
      DB.remove_by_id(@sessions_table, id)
    end

    :ok
  end

  defp authenticate(conn) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         session when not is_nil(session) <- DB.get(@sessions_table, %{"token" => token}),
         true <- (session["expires_at"] || 0) > System.system_time(:second),
         user when not is_nil(user) <- DB.get(@users_table, %{"username" => session["username"]}) do
      {:ok, user, token}
    else
      _ -> :unauthorized
    end
  end

  defp with_auth(conn, fun) do
    case authenticate(conn) do
      {:ok, user, token} -> fun.(user, token)
      :unauthorized -> Api.error(conn, 401, "unauthorized")
    end
  end

  defp bound_to_other?(uid, username) do
    @users_table
    |> DB.all()
    |> Enum.any?(fn u -> u["username"] != username and uid in (u["cards"] || []) end)
  end

  defp public_user(user) do
    %{"username" => user["username"], "cards" => user["cards"] || [], "created_at" => user["created_at"]}
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

  defp my_game_ids(game, cards) do
    game["profile_table"]
    |> DB.search_with_ids(%{})
    |> Enum.filter(fn {_id, doc} -> doc["card"] in cards end)
    |> Enum.map(fn {_id, doc} -> doc[game["id_field"]] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp name_map(game) do
    game["profile_table"]
    |> DB.all()
    |> Map.new(fn doc -> {doc[game["id_field"]], Api.profile_name(doc)} end)
    |> Map.delete(nil)
  end

  defp score_of(row, st) do
    case row[st["score_field"]] do
      n when is_number(n) -> n
      _ -> 0
    end
  end
end
