defmodule BaconNet.AccountTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias BaconNet.DB

  @card_uid "E004009999999999"

  setup do
    DB.drop_table("webui_users")
    DB.drop_table("webui_sessions")
    DB.drop_table("test_profile")

    on_exit(fn ->
      DB.drop_table("webui_users")
      DB.drop_table("webui_sessions")
      DB.drop_table("test_profile")
    end)

    :ok
  end

  defp call(method, path, body \\ nil, token \\ nil) do
    conn =
      if body do
        conn(method, path, Jason.encode!(body))
        |> Plug.Conn.put_req_header("content-type", "application/json")
      else
        conn(method, path)
      end

    conn =
      if token, do: Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}"), else: conn

    BaconNet.Router.call(conn, BaconNet.Router.init([]))
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
  end

  test "login, me, logout" do
    %{"token" => token} = json(register())

    conn = call(:post, "/account/api/login", %{"username" => "Player1", "password" => "password123"})
    assert conn.status == 200
    assert %{"token" => _} = json(conn)

    assert call(:post, "/account/api/login", %{"username" => "player1", "password" => "wrong"}).status == 401

    conn = call(:get, "/account/api/me", nil, token)
    assert %{"username" => "player1", "cards" => []} = json(conn)

    assert call(:post, "/account/api/logout", nil, token).status == 204
    assert call(:get, "/account/api/me", nil, token).status == 401
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

    DB.insert("iidx_scores", %{"iidx_id" => 12_345_678, "music_id" => 1000, "chart_id" => 2, "ex_score" => 1500})
    DB.insert("iidx_scores", %{"iidx_id" => 99_999_999, "music_id" => 1000, "chart_id" => 2, "ex_score" => 2000})

    # alice sees only her own profile
    conn = call(:get, "/account/api/profiles", nil, t1)
    assert %{"profiles" => [p]} = json(conn)
    assert p["game"] == "iidx"
    assert p["name"] == "ＡＬＩＣＥ"
    assert p["game_id"] == 12_345_678
    assert p["versions"] == ["33"]

    # bob sees nothing
    assert %{"profiles" => []} = json(call(:get, "/account/api/profiles", nil, t2))

    # alice can fetch and patch her profile; card reassignment is stripped
    conn = call(:get, "/account/api/profiles/iidx_profile/#{profile_id}", nil, t1)
    assert conn.status == 200

    conn =
      call(:patch, "/account/api/profiles/iidx_profile/#{profile_id}",
        %{"pin" => "9999", "card" => "E004000000000000"},
        t1
      )

    assert conn.status == 200
    doc = json(conn)
    assert doc["pin"] == "9999"
    assert doc["card"] == @card_uid

    # bob cannot touch alice's profile
    assert call(:get, "/account/api/profiles/iidx_profile/#{profile_id}", nil, t2).status == 404
    assert call(:patch, "/account/api/profiles/iidx_profile/#{profile_id}", %{"pin" => "0"}, t2).status == 404

    # unknown table is rejected even for the owner
    assert call(:get, "/account/api/profiles/webui_users/1", nil, t1).status == 404

    # scores: alice gets only her own rows
    conn = call(:get, "/account/api/scores", nil, t1)
    %{"games" => [g]} = json(conn)
    assert g["game"] == "iidx"
    assert g["ids"] == [12_345_678]
    assert [%{"ex_score" => 1500}] = g["tables"]["iidx_scores"]
  after
    DB.drop_table("iidx_profile")
    DB.drop_table("iidx_scores")
  end

  test "rankings aggregate best scores across players" do
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

    DB.insert("iidx_scores_best", %{"iidx_id" => 111, "music_id" => 1000, "chart_id" => 2, "ex_score" => 1800})
    DB.insert("iidx_scores_best", %{"iidx_id" => 222, "music_id" => 1000, "chart_id" => 2, "ex_score" => 1900})
    DB.insert("iidx_scores_best", %{"iidx_id" => 111, "music_id" => 1001, "chart_id" => 2, "ex_score" => 700})

    conn = call(:get, "/account/api/rankings", nil, token)
    %{"games" => [g]} = json(conn)
    assert g["game"] == "iidx"

    [first, second, other_song] = g["entries"]
    assert {first["song"], first["rank"], first["score"], first["name"]} == {1000, 1, 1900, "ＳＥＣＯＮＤ"}
    assert {second["song"], second["rank"], second["score"], second["name"]} == {1000, 2, 1800, "ＴＯＰ"}
    assert {other_song["song"], other_song["rank"]} == {1001, 1}
  after
    DB.drop_table("iidx_profile")
    DB.drop_table("iidx_scores_best")
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

    DB.update("webui_users", %{"banned" => true}, %{"username" => "banned1"})

    # login is rejected with 403 account_banned
    conn = call(:post, "/account/api/login", %{"username" => "banned1", "password" => "password123"})
    assert conn.status == 403
    assert %{"error" => "account_banned"} = json(conn)

    # existing session is rejected too
    assert call(:get, "/account/api/me", nil, token).status == 401

    # unban restores login
    DB.update("webui_users", %{"banned" => false}, %{"username" => "banned1"})
    assert call(:post, "/account/api/login", %{"username" => "banned1", "password" => "password123"}).status == 200
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
end
