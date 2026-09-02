defmodule BaconNet.AccountTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias BaconNet.{Accounts, DB}
  alias BaconNet.Repo

  @card_uid "E004009999999999"

  setup do
    cleanup()

    on_exit(&cleanup/0)

    :ok
  end

  defp cleanup do
    Repo.delete_all(BaconNet.Accounts.Session)
    Repo.delete_all(BaconNet.Accounts.Card)
    Repo.delete_all(BaconNet.Accounts.Account)
    DB.drop_table("test_profile")
  end

  defp call(method, path, body \\ nil, token \\ nil, opts \\ []) do
    conn =
      if body do
        conn(method, path, Jason.encode!(body))
        |> Plug.Conn.put_req_header("content-type", "application/json")
      else
        conn(method, path)
      end

    conn =
      if token, do: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}"), else: conn

    conn =
      if opts[:cookie],
        do: put_req_cookie(conn, "bacon_session", opts[:cookie]),
        else: conn

    conn =
      if opts[:csrf],
        do: Plug.Conn.put_req_header(conn, "x-csrf-requested-with", "fetch"),
        else: conn

    BaconNet.Router.call(conn, BaconNet.Router.init([]))
  end

  defp set_cookie(conn, name) do
    conn.resp_headers
    |> Enum.filter(fn {k, _} -> k == "set-cookie" end)
    |> Enum.map(fn {_, v} -> v end)
    |> Enum.find("", &String.starts_with?(&1, "#{name}="))
  end

  defp json(conn), do: Jason.decode!(conn.resp_body)

  defp register(username \\ "player1", password \\ "password123") do
    call(:post, "/account/api/register", %{"username" => username, "password" => password})
  end

  test "register validates input" do
    assert register("ab", "password123").status == 400
    assert register("player1", "short").status == 400

    conn = register()
    assert conn.status == 201
    assert %{"token" => _, "username" => "player1", "expires_at" => _} = json(conn)

    assert register().status == 409
    # differently cased spelling conflicts too
    assert register("PLAYER1").status == 409
  end

  test "login, me, logout" do
    %{"token" => token} = json(register())

    conn =
      call(:post, "/account/api/login", %{"username" => "Player1", "password" => "password123"})

    assert conn.status == 200
    assert %{"token" => _} = json(conn)

    assert call(:post, "/account/api/login", %{"username" => "player1", "password" => "wrong"}).status ==
             401

    conn = call(:get, "/account/api/me", nil, token)
    assert %{"username" => "player1", "cards" => []} = json(conn)

    assert call(:post, "/account/api/logout", nil, token).status == 204
    assert call(:get, "/account/api/me", nil, token).status == 401
  end

  test "login and register set an HttpOnly session cookie" do
    conn = register()
    cookie = set_cookie(conn, "bacon_session")
    assert cookie =~ "HttpOnly"
    assert cookie =~ "SameSite=Strict"
    assert cookie =~ "path=/"
    refute cookie =~ "secure"

    conn =
      call(:post, "/account/api/login", %{"username" => "player1", "password" => "password123"})

    assert set_cookie(conn, "bacon_session") =~ "HttpOnly"
  end

  test "cookie-authenticated requests work; mutations require the CSRF header" do
    %{"token" => token} = json(register())

    # cookie alone authenticates safe methods
    conn = call(:get, "/account/api/me", nil, nil, cookie: token)
    assert conn.status == 200
    assert json(conn)["username"] == "player1"

    # a mutating request with only the cookie is rejected
    conn = call(:post, "/account/api/cards", %{"card" => @card_uid}, nil, cookie: token)
    assert conn.status == 403
    assert %{"error" => "csrf_header_required"} = json(conn)

    # with the CSRF header the same request goes through
    conn =
      call(:post, "/account/api/cards", %{"card" => @card_uid}, nil,
        cookie: token,
        csrf: true
      )

    assert conn.status == 200
    assert %{"cards" => [@card_uid]} = json(conn)

    # cookie + header also authenticates non-mutating routes
    assert call(:get, "/account/api/profiles", nil, nil, cookie: token, csrf: true).status == 200

    # header auth stays exempt from the CSRF rule
    assert call(:post, "/account/api/cards", %{"card" => "E004001111111111"}, token).status == 200

    # an unknown cookie is still just unauthorized
    assert call(:get, "/account/api/me", nil, nil, cookie: "bogus").status == 401
  end

  test "logout revokes the session and clears the cookie" do
    %{"token" => token} = json(register())

    conn = call(:post, "/account/api/logout", nil, nil, cookie: token, csrf: true)
    assert conn.status == 204

    cleared = set_cookie(conn, "bacon_session")
    assert cleared =~ "max-age=0"

    # the cookie no longer authenticates
    assert call(:get, "/account/api/me", nil, nil, cookie: token).status == 401
  end

  test "me exposes the admin flag" do
    %{"token" => token} = json(register())

    conn = call(:get, "/account/api/me", nil, token)
    assert json(conn)["admin"] == false

    "player1"
    |> Accounts.get_by_username()
    |> Ecto.Changeset.change(admin: true)
    |> Repo.update!()

    conn = call(:get, "/account/api/me", nil, token)
    assert json(conn)["admin"] == true
  end

  test "sessions store only the token digest; revoked and expired tokens are rejected" do
    %{"token" => token} = json(register())

    session = Repo.get_by!(BaconNet.Accounts.Session, account_id: account_id("player1"))
    assert session.token_digest == Accounts.hash_token(token)
    refute inspect(session) =~ token

    # the plaintext token still authenticates and logout revokes it
    assert call(:get, "/account/api/me", nil, token).status == 200
    assert call(:post, "/account/api/logout", nil, token).status == 204
    assert call(:get, "/account/api/me", nil, token).status == 401

    # an expired token is rejected
    %{"token" => expired} =
      json(
        call(:post, "/account/api/login", %{
          "username" => "player1",
          "password" => "password123"
        })
      )

    Accounts.Session
    |> Repo.get_by!(token_digest: Accounts.hash_token(expired))
    |> Ecto.Changeset.change(expires_at: System.system_time(:second) - 1)
    |> Repo.update!()

    assert call(:get, "/account/api/me", nil, expired).status == 401
  end

  test "oversized passwords are rejected before hashing" do
    big = String.duplicate("a", 1025)

    conn = register("bigpw", big)
    assert conn.status == 400
    assert %{"error" => "password_too_long"} = json(conn)

    # exactly at the limit is fine
    assert register("limitpw", String.duplicate("a", 1024)).status == 201

    # login with an oversized password is rejected without hashing
    assert call(:post, "/account/api/login", %{"username" => "limitpw", "password" => big}).status ==
             401

    assert call(:post, "/account/api/login", %{
             "username" => "limitpw",
             "password" => String.duplicate("a", 1024)
           }).status == 200
  end

  test "card binding with normalization and uniqueness" do
    %{"token" => t1} = json(register("alice", "password123"))
    %{"token" => t2} = json(register("bob", "password123"))

    conn = call(:post, "/account/api/cards", %{"card" => @card_uid}, t1)
    assert conn.status == 200
    assert %{"cards" => [@card_uid], "bound" => %{"uid" => @card_uid}} = json(conn)

    # duplicate bind to same account
    assert call(:post, "/account/api/cards", %{"card" => @card_uid}, t1).status == 409
    # same card bound to another account
    assert call(:post, "/account/api/cards", %{"card" => @card_uid}, t2).status == 409
    # garbage input
    assert call(:post, "/account/api/cards", %{"card" => "!!!"}, t1).status == 400

    conn = call(:delete, "/account/api/cards/#{@card_uid}", nil, t1)
    assert conn.status == 200
    assert %{"cards" => []} = json(conn)
    assert call(:delete, "/account/api/cards/#{@card_uid}", nil, t1).status == 404
  end

  test "profiles and scores are ownership-checked" do
    %{"token" => t1} = json(register("alice", "password123"))
    %{"token" => t2} = json(register("bob", "password123"))

    call(:post, "/account/api/cards", %{"card" => @card_uid}, t1)

    {profile_id, _} =
      DB.insert_with_id("iidx_profile", %{
        "card" => @card_uid,
        "iidx_id" => 12_345_678,
        "pin" => "1234",
        "version" => %{"33" => %{"djname" => "ＡＬＩＣＥ", "turntable" => 1}}
      })

    DB.insert_with_id("iidx_profile", %{
      "card" => "E004000000000000",
      "iidx_id" => 99_999_999,
      "version" => %{"33" => %{"djname" => "ＳＴＲＡＮＧＥＲ"}}
    })

    DB.insert("iidx_scores", %{
      "iidx_id" => 12_345_678,
      "music_id" => 1000,
      "chart_id" => 2,
      "ex_score" => 1500
    })

    DB.insert("iidx_scores", %{
      "iidx_id" => 99_999_999,
      "music_id" => 1000,
      "chart_id" => 2,
      "ex_score" => 2000
    })

    # alice sees only her own profile
    conn = call(:get, "/account/api/profiles", nil, t1)
    assert %{"profiles" => [p]} = json(conn)
    assert p["game"] == "iidx"
    assert p["name"] == "ＡＬＩＣＥ"
    assert p["game_id"] == 12_345_678
    assert p["versions"] == ["33"]

    # bob sees nothing
    assert %{"profiles" => []} = json(call(:get, "/account/api/profiles", nil, t2))

    # alice can fetch her profile
    conn = call(:get, "/account/api/profiles/iidx_profile/#{profile_id}", nil, t1)
    assert conn.status == 200

    # bob cannot touch alice's profile
    assert call(:get, "/account/api/profiles/iidx_profile/#{profile_id}", nil, t2).status == 404

    assert call(
             :patch,
             "/account/api/profiles/iidx_profile/#{profile_id}",
             %{"pin" => "0000"},
             t2
           ).status ==
             404

    # unknown table is rejected even for the owner
    assert call(:get, "/account/api/profiles/accounts/1", nil, t1).status == 404

    # scores: alice gets only her own rows, in the paginated shape
    conn = call(:get, "/account/api/scores", nil, t1)
    %{"items" => [row], "next_cursor" => nil} = json(conn)
    assert row["ex_score"] == 1500
    assert row["game"] == "iidx"
    assert row["table"] == "iidx_scores"
  after
    DB.drop_table("iidx_profile")
    DB.drop_table("iidx_scores")
  end

  test "profile PATCH only accepts allowlisted fields" do
    %{"token" => token} = json(register("alice", "password123"))
    call(:post, "/account/api/cards", %{"card" => @card_uid}, token)

    {profile_id, _} =
      DB.insert_with_id("iidx_profile", %{
        "card" => @card_uid,
        "iidx_id" => 12_345_678,
        "pin" => "1234",
        "version" => %{"33" => %{"djname" => "ＡＬＩＣＥ"}}
      })

    patch = fn fields ->
      call(:patch, "/account/api/profiles/iidx_profile/#{profile_id}", fields, token)
    end

    # non-allowlisted fields are rejected outright (never silently stripped)
    assert patch.(%{"card" => "E004000000000000"}).status == 400
    assert patch.(%{"_id" => 1}).status == 400
    assert patch.(%{"iidx_id" => 1}).status == 400
    assert patch.(%{"pin" => "9999", "card" => "E004000000000000"}).status == 400
    assert patch.(%{}).status == 400

    # invalid pin values
    assert patch.(%{"pin" => "abc"}).status == 400
    assert patch.(%{"pin" => "12345"}).status == 400
    assert patch.(%{"pin" => 1234}).status == 400

    # invalid version shapes
    assert patch.(%{"version" => "33"}).status == 400
    assert patch.(%{"version" => %{"x" => %{}}}).status == 400
    assert patch.(%{"version" => %{"33" => %{"nested" => %{"bad" => 1}}}}).status == 400

    # nothing was written by any of the rejected patches
    doc = DB.get_by_id("iidx_profile", profile_id)
    assert doc["card"] == @card_uid
    assert doc["pin"] == "1234"

    # a valid patch merges per version key and keeps other versions
    conn =
      patch.(%{
        "pin" => "9999",
        "version" => %{"33" => %{"djname" => "ＮＥＷ"}, "30" => %{"djname" => "ＯＬＤ"}}
      })

    assert conn.status == 200
    doc = json(conn)
    assert doc["pin"] == "9999"
    assert doc["card"] == @card_uid
    assert doc["version"]["33"]["djname"] == "ＮＥＷ"
    assert doc["version"]["30"]["djname"] == "ＯＬＤ"
  after
    DB.drop_table("iidx_profile")
  end

  test "scores paginate with a stable cursor order" do
    %{"token" => token} = json(register("alice", "password123"))
    call(:post, "/account/api/cards", %{"card" => @card_uid}, token)

    DB.insert("iidx_profile", %{"card" => @card_uid, "iidx_id" => 42})

    for i <- 1..5 do
      DB.insert("iidx_scores", %{
        "iidx_id" => 42,
        "music_id" => 1000 + i,
        "chart_id" => 1,
        "ex_score" => i
      })
    end

    # first page
    conn = call(:get, "/account/api/scores?limit=2", nil, token)
    %{"items" => first, "next_cursor" => c1} = json(conn)
    assert Enum.map(first, & &1["ex_score"]) == [1, 2]
    assert is_binary(c1)

    # middle page
    conn = call(:get, "/account/api/scores?limit=2&cursor=#{c1}", nil, token)
    %{"items" => second, "next_cursor" => c2} = json(conn)
    assert Enum.map(second, & &1["ex_score"]) == [3, 4]
    assert is_binary(c2)

    # last page has no next cursor
    conn = call(:get, "/account/api/scores?limit=2&cursor=#{c2}", nil, token)
    %{"items" => third, "next_cursor" => nil} = json(conn)
    assert Enum.map(third, & &1["ex_score"]) == [5]

    # past the end: empty page
    conn = call(:get, "/account/api/scores?cursor=#{encode_cursor(999_999)}", nil, token)
    assert %{"items" => [], "next_cursor" => nil} = json(conn)

    # invalid cursors and limits are 400
    assert call(:get, "/account/api/scores?cursor=not-a-cursor", nil, token).status == 400

    assert call(
             :get,
             "/account/api/scores?cursor=#{Base.url_encode64("{}", padding: false)}",
             nil,
             token
           ).status == 400

    assert call(:get, "/account/api/scores?limit=0", nil, token).status == 400
    assert call(:get, "/account/api/scores?limit=abc", nil, token).status == 400

    # limit is clamped to 200
    conn = call(:get, "/account/api/scores?limit=9999", nil, token)
    assert conn.status == 200
    assert length(json(conn)["items"]) == 5
  after
    DB.drop_table("iidx_profile")
    DB.drop_table("iidx_scores")
  end

  test "rankings require game+song+chart and return a bounded SQL top-N" do
    %{"token" => token} = json(register())

    DB.insert_with_id("iidx_profile", %{
      "card" => "E004000000000001",
      "iidx_id" => 111,
      "version" => %{"33" => %{"djname" => "ＴＯＰ"}}
    })

    DB.insert_with_id("iidx_profile", %{
      "card" => "E004000000000002",
      "iidx_id" => 222,
      "version" => %{"33" => %{"djname" => "ＳＥＣＯＮＤ"}}
    })

    DB.insert("iidx_scores_best", %{
      "iidx_id" => 111,
      "music_id" => 1000,
      "chart_id" => 2,
      "ex_score" => 1800
    })

    DB.insert("iidx_scores_best", %{
      "iidx_id" => 222,
      "music_id" => 1000,
      "chart_id" => 2,
      "ex_score" => 1900
    })

    DB.insert("iidx_scores_best", %{
      "iidx_id" => 111,
      "music_id" => 1001,
      "chart_id" => 2,
      "ex_score" => 700
    })

    # missing/invalid parameters are 400
    assert call(:get, "/account/api/rankings", nil, token).status == 400
    assert call(:get, "/account/api/rankings?game=iidx", nil, token).status == 400

    assert call(:get, "/account/api/rankings?game=nope&song=1000&chart=2", nil, token).status ==
             400

    assert call(:get, "/account/api/rankings?game=iidx&song=abc&chart=2", nil, token).status ==
             400

    conn = call(:get, "/account/api/rankings?game=iidx&song=1000&chart=2", nil, token)
    assert conn.status == 200

    %{
      "game" => "iidx",
      "table" => "iidx_scores_best",
      "song" => 1000,
      "chart" => 2,
      "items" => items
    } =
      json(conn)

    assert [
             %{"rank" => 1, "score" => 1900, "name" => "ＳＥＣＯＮＤ"},
             %{"rank" => 2, "score" => 1800, "name" => "ＴＯＰ"}
           ] = items

    # bounded top-N
    conn = call(:get, "/account/api/rankings?game=iidx&song=1000&chart=2&limit=1", nil, token)
    assert [%{"rank" => 1, "score" => 1900}] = json(conn)["items"]

    # a different song has its own ranking
    conn = call(:get, "/account/api/rankings?game=iidx&song=1001&chart=2", nil, token)
    assert [%{"rank" => 1, "score" => 700, "name" => "ＴＯＰ"}] = json(conn)["items"]

    # no scores: empty items
    conn = call(:get, "/account/api/rankings?game=iidx&song=9999&chart=2", nil, token)
    assert %{"items" => []} = json(conn)
  after
    DB.drop_table("iidx_profile")
    DB.drop_table("iidx_scores_best")
  end

  test "concurrent registrations of the same username commit exactly once" do
    results =
      ["player1", "PLAYER1", "Player1", "pLaYeR1"]
      |> Task.async_stream(fn username -> register(username).status end,
        max_concurrency: 4,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, status} -> status end)

    assert Enum.count(results, &(&1 == 201)) == 1
    assert Enum.count(results, &(&1 == 409)) == 3
    assert length(Repo.all(BaconNet.Accounts.Account)) == 1
  end

  test "concurrent binds of the same card leave exactly one owner" do
    %{"token" => t1} = json(register("alice", "password123"))
    %{"token" => t2} = json(register("bob", "password123"))

    results =
      [t1, t2, t1, t2]
      |> Task.async_stream(
        fn token -> call(:post, "/account/api/cards", %{"card" => @card_uid}, token).status end,
        max_concurrency: 4,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, status} -> status end)

    assert Enum.count(results, &(&1 == 200)) == 1
    assert Enum.count(results, &(&1 == 409)) == 3

    assert [%{card_uid: @card_uid}] =
             Repo.all(BaconNet.Accounts.Card) |> Enum.map(&Map.take(&1, [:card_uid]))
  end

  test "registration rolls back when the session step fails" do
    before_count = Repo.aggregate(BaconNet.Accounts.Account, :count)

    assert {:error, :boom} =
             Accounts.register("rollback1", "password123",
               before_commit: fn _account, _session -> {:error, :boom} end
             )

    assert Repo.aggregate(BaconNet.Accounts.Account, :count) == before_count
    assert Accounts.get_by_username("rollback1") == nil
    assert Repo.all(BaconNet.Accounts.Session) == []
  end

  test "unauthenticated requests are rejected" do
    assert call(:get, "/account/api/me").status == 401
    assert call(:get, "/account/api/profiles").status == 401
    assert call(:get, "/account/api/scores").status == 401
    assert call(:get, "/account/api/rankings").status == 401
  end

  test "banned users cannot log in and existing sessions die" do
    %{"token" => token} = json(register("banned1", "password123"))

    # session works before the ban
    assert call(:get, "/account/api/me", nil, token).status == 200

    account = Accounts.get_by_username("banned1")
    Accounts.set_banned(account, true)

    # login is rejected with 403 account_banned
    conn =
      call(:post, "/account/api/login", %{"username" => "banned1", "password" => "password123"})

    assert conn.status == 403
    assert %{"error" => "account_banned"} = json(conn)

    # existing session is rejected too
    assert call(:get, "/account/api/me", nil, token).status == 401

    # unban restores login
    "banned1" |> Accounts.get_by_username() |> Accounts.set_banned(false)

    assert call(:post, "/account/api/login", %{
             "username" => "banned1",
             "password" => "password123"
           }).status == 200
  end

  test "games metadata is public" do
    conn = call(:get, "/account/api/games")
    assert conn.status == 200
    games = json(conn)["games"]
    assert Enum.find(games, &(&1["key"] == "iidx"))["score_tables"] |> length() == 2
  end

  test "manage API obeys admin token when configured" do
    Application.put_env(:bacon_net, :admin_token, "s3cret")

    try do
      assert call(:get, "/manage/api/tables").status == 401

      conn =
        conn(:get, "/manage/api/tables")
        |> Plug.Conn.put_req_header("authorization", "Bearer s3cret")
        |> BaconNet.Router.call(BaconNet.Router.init([]))

      assert conn.status == 200
    after
      Application.delete_env(:bacon_net, :admin_token)
    end
  end

  defp account_id(username) do
    Accounts.get_by_username(username).id
  end

  defp encode_cursor(seq), do: seq |> Jason.encode!() |> Base.url_encode64(padding: false)
end
