defmodule BaconNet.Modules.Gitadora.Api do
  @moduledoc "Port of modules/gitadora/api.py."

  import Plug.Conn, only: [send_resp: 3]

  alias BaconNet.{Api, Card, DB}

  def routes do
    %{
      prefix: "/gfdm",
      tag: "api_gfdm",
      handlers: [],
      api: [
        {:get, ["profiles"], :gfdm_profiles},
        {:get, ["profiles", :gitadora_id], :gfdm_profile_id},
        {:patch, ["profiles", :gitadora_id], :gfdm_profile_id_patch},
        {:patch, ["profiles", :gitadora_id, :version], :gfdm_profile_id_version_patch},
        {:get, ["card", :card], :gfdm_card_to_profile},
        {:get, ["drummania", "scores"], :dm_scores},
        {:get, ["guitarfreaks", "scores"], :gf_scores},
        {:get, ["drummania", "scores", :gitadora_id], :dm_scores_id},
        {:get, ["guitarfreaks", "scores", :gitadora_id], :gf_scores_id},
        {:get, ["drummania", "scores_best"], :dm_scores_best},
        {:get, ["guitarfreaks", "scores_best"], :gf_scores_best},
        {:get, ["drummania", "scores_best", :gitadora_id], :dm_scores_best_id},
        {:get, ["guitarfreaks", "scores_best", :gitadora_id], :gf_scores_best_id},
        {:get, ["drummania", "mcode", :mcode, "all"], :dm_scores_mcode_all},
        {:get, ["guitarfreaks", "mcode", :mcode, "all"], :gf_scores_mcode_all},
        {:get, ["drummania", "mcode", :mcode, "best"], :dm_scores_id_best},
        {:get, ["guitarfreaks", "mcode", :mcode, "best"], :gf_scores_id_best}
      ]
    }
  end

  def gfdm_profiles(conn, _params) do
    Api.json(conn, DB.all("gitadora_profile"))
  end

  def gfdm_profile_id(conn, %{"gitadora_id" => gitadora_id}) do
    gitadora_id = gitadora_id |> numeric_only() |> String.to_integer()
    Api.json(conn, DB.get("gitadora_profile", %{"gitadora_id" => gitadora_id}))
  end

  def gfdm_profile_id_patch(conn, %{"gitadora_id" => gitadora_id}) do
    gitadora_id = gitadora_id |> numeric_only() |> String.to_integer()
    profile = DB.get("gitadora_profile", %{"gitadora_id" => gitadora_id})

    profile =
      profile
      |> Map.put("card", conn.body_params["card"])
      |> Map.put("pin", conn.body_params["pin"])

    DB.upsert("gitadora_profile", profile, %{"gitadora_id" => gitadora_id})

    send_resp(conn, 204, "")
  end

  def gfdm_profile_id_version_patch(conn, %{"gitadora_id" => gitadora_id, "version" => version}) do
    gitadora_id = gitadora_id |> numeric_only() |> String.to_integer()
    profile = DB.get("gitadora_profile", %{"gitadora_id" => gitadora_id})
    version = version |> String.to_integer()
    version_key = to_string(version)
    game_profile = Map.get(profile["version"], version_key, %{})

    game_profile =
      game_profile
      |> Map.put("game_version", conn.body_params["game_version"])
      |> Map.put("name", conn.body_params["name"])
      |> Map.put("title", conn.body_params["title"])
      |> Map.put("rival_card_ids", conn.body_params["rival_card_ids"])

    profile =
      Map.put(
        profile,
        "version",
        Map.put(Map.get(profile, "version", %{}), version_key, game_profile)
      )

    DB.upsert("gitadora_profile", profile, %{"gitadora_id" => gitadora_id})

    send_resp(conn, 204, "")
  end

  def gfdm_card_to_profile(conn, %{"card" => card}) do
    card = String.upcase(card)

    lookalike = %{
      "I" => "1",
      "O" => "0",
      "Q" => "0",
      "V" => "U"
    }

    card = Enum.reduce(lookalike, card, fn {k, v}, c -> String.replace(c, k, v) end)

    uid =
      if String.starts_with?(card, "E004") or String.starts_with?(card, "012E") do
        card = keep_chars(card, ~c"0123456789ABCDEF")
        _kid = Card.to_konami_id(card)
        card
      else
        card = keep_chars(card, Card.valid_characters() |> :binary.bin_to_list())
        Card.to_uid(card)
      end

    Api.json(conn, DB.get("gitadora_profile", %{"card" => uid}))
  end

  def dm_scores(conn, _params) do
    Api.json(conn, DB.all("drummania_scores"))
  end

  def gf_scores(conn, _params) do
    Api.json(conn, DB.all("guitarfreaks_scores"))
  end

  def dm_scores_id(conn, %{"gitadora_id" => gitadora_id}) do
    gitadora_id = gitadora_id |> numeric_only() |> String.to_integer()
    Api.json(conn, DB.search("drummania_scores", %{"gitadora_id" => gitadora_id}))
  end

  def gf_scores_id(conn, %{"gitadora_id" => gitadora_id}) do
    gitadora_id = gitadora_id |> numeric_only() |> String.to_integer()
    Api.json(conn, DB.search("guitarfreaks_scores", %{"gitadora_id" => gitadora_id}))
  end

  def dm_scores_best(conn, _params) do
    Api.json(conn, DB.all("drummania_scores_best"))
  end

  def gf_scores_best(conn, _params) do
    Api.json(conn, DB.all("guitarfreaks_scores_best"))
  end

  def dm_scores_best_id(conn, %{"gitadora_id" => gitadora_id}) do
    gitadora_id = gitadora_id |> numeric_only() |> String.to_integer()
    Api.json(conn, DB.search("drummania_scores_best", %{"gitadora_id" => gitadora_id}))
  end

  def gf_scores_best_id(conn, %{"gitadora_id" => gitadora_id}) do
    gitadora_id = gitadora_id |> numeric_only() |> String.to_integer()
    Api.json(conn, DB.search("guitarfreaks_scores_best", %{"gitadora_id" => gitadora_id}))
  end

  def dm_scores_mcode_all(conn, %{"mcode" => mcode}) do
    Api.json(conn, DB.search("drummania_scores", %{"mcode" => String.to_integer(mcode)}))
  end

  def gf_scores_mcode_all(conn, %{"mcode" => mcode}) do
    Api.json(conn, DB.search("guitarfreaks_scores", %{"mcode" => String.to_integer(mcode)}))
  end

  def dm_scores_id_best(conn, %{"mcode" => mcode}) do
    Api.json(conn, DB.search("drummania_scores_best", %{"mcode" => String.to_integer(mcode)}))
  end

  def gf_scores_id_best(conn, %{"mcode" => mcode}) do
    Api.json(conn, DB.search("guitarfreaks_scores_best", %{"mcode" => String.to_integer(mcode)}))
  end

  defp numeric_only(s) do
    s |> :binary.bin_to_list() |> Enum.filter(&(&1 in ~c"0123456789")) |> IO.iodata_to_binary()
  end

  defp keep_chars(s, chars) do
    s |> :binary.bin_to_list() |> Enum.filter(&(&1 in chars)) |> IO.iodata_to_binary()
  end
end
