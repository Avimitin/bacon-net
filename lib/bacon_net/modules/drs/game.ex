defmodule BaconNet.Modules.Drs.Game do
  @moduledoc "Port of modules/drs/game.py."

  alias BaconNet.{Core, DB, E, Kbinxml, Scores, XNode}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"game", "get_common", :drs_game_get_common},
        # the Python routes carry a "{player}" path parameter
        # (get_playdata_{player} etc.); the dispatcher only supports the
        # "{ver}" token and cannot extract it from a trailing position, so
        # the two player variants are registered literally (DANCERUSH is a
        # 2-player game and no handler reads the parameter)
        {"game", "get_playdata_1", :drs_game_get_playdata},
        {"game", "get_playdata_2", :drs_game_get_playdata},
        {"game", "lock_multi_login_1", :drs_game_lock_multi_login},
        {"game", "lock_multi_login_2", :drs_game_lock_multi_login},
        {"game", "sign_up_1", :drs_game_sign_up},
        {"game", "sign_up_2", :drs_game_sign_up},
        {"game", "get_musicscore_1", :drs_game_get_musicscore},
        {"game", "get_musicscore_2", :drs_game_get_musicscore},
        {"game", "save_musicscore", :drs_save_musicscore},
        # the Python file defines drs_save_musicscore twice; the second def
        # (save_playdata) is renamed here since Elixir has no shadowing
        {"game", "save_playdata", :drs_save_playdata}
      ]
    }
  end

  @info_attrs [
    "title_name",
    "title_yomigana",
    "artist_name",
    "artist_yomigana",
    "bpm_max",
    "bpm_min",
    # "distribution_date",
    "volume",
    "bg_no",
    "region",
    # "limitation_type",
    # "price",
    "genre",
    "play_video_flags",
    "is_fixed",
    "version",
    "demo_pri",
    "license",
    "color1",
    "color2",
    "color3"
  ]

  @fumen_attrs ["1b", "1a", "2b", "2a"]

  defp get_profile(cid) do
    DB.get("dancerush_profile", %{"card" => cid})
  end

  defp get_game_profile(cid, game_version) do
    profile = get_profile(cid)
    get_in(profile || %{}, ["version", to_string(game_version)])
  end

  defp get_id_from_profile(cid) do
    profile = DB.get("dancerush_profile", %{"card" => cid})

    djid = Integer.to_string(profile["drs_id"]) |> String.pad_leading(8, "0")
    djid_split = binary_part(djid, 0, 4) <> "-" <> binary_part(djid, 4, 4)

    {profile["drs_id"], djid_split}
  end

  def drs_game_get_common(conn) do
    {info, conn} = Core.process_request(conn)

    # TODO: server side song unlock is incomplete, use hex edits for now
    songs =
      case load_xml(["modules/drs/music-info-base.xml", "music-info-base.xml"], :utf8) do
        nil ->
          []

        root ->
          Enum.map(root.children, fn entry ->
            mid = XNode.attr(entry, "id")

            attrs =
              Map.new(@info_attrs, fn atr ->
                value = entry |> XNode.child("info") |> XNode.child(atr) |> text()
                value = if value == nil, do: "", else: value
                {atr, value}
              end)

            difnums =
              Map.new(@fumen_attrs, fn atr ->
                value =
                  entry
                  |> XNode.child("difficulty")
                  |> XNode.child("fumen_" <> atr)
                  |> XNode.child("difnum")
                  |> text()

                # songs[mid][f"{atr}_playable"] = entry.find(f"difficulty/fumen_{atr}/playable").text
                {"#{atr}_difnum", value}
              end)

            {mid, Map.merge(attrs, difnums)}
          end)
      end

    music_nodes =
      for {mid, s} <- songs do
        E.e(
          "music",
          [
            E.e("info", [
              E.e("title_name", s["title_name"], __type: "str"),
              E.e("title_yomigana", s["title_yomigana"], __type: "str"),
              E.e("artist_name", s["artist_name"], __type: "str"),
              E.e("artist_yomigana", s["artist_yomigana"], __type: "str"),
              E.e("bpm_max", s["bpm_max"], __type: "u32"),
              E.e("bpm_min", s["bpm_min"], __type: "u32"),
              E.e("distribution_date", 20_180_427, __type: "u32"),
              E.e("volume", s["volume"], __type: "u16"),
              E.e("bg_no", s["bg_no"], __type: "u16"),
              E.e("region", "JUAKYC", __type: "str"),
              E.e("limitation_type", 3, __type: "u8"),
              E.e("price", 0, __type: "s32"),
              E.e("genre", s["genre"], __type: "u32"),
              E.e("play_video_flags", s["play_video_flags"], __type: "u32"),
              E.e("is_fixed", s["is_fixed"], __type: "u8"),
              E.e("version", s["version"], __type: "u8"),
              E.e("demo_pri", s["demo_pri"], __type: "u8"),
              E.e("license", s["license"], __type: "str"),
              E.e("color1", String.to_integer(s["color1"], 16), __type: "u32"),
              E.e("color2", String.to_integer(s["color2"], 16), __type: "u32"),
              E.e("color3", String.to_integer(s["color3"], 16), __type: "u32")
            ]),
            E.e("difficulty", [
              E.e("fumen_1b", [
                E.e("difnum", s["1b_difnum"], __type: "u8"),
                E.e("playable", 1, __type: "u8")
              ]),
              E.e("fumen_1a", [
                E.e("difnum", s["1a_difnum"], __type: "u8"),
                E.e("playable", 1, __type: "u8")
              ]),
              E.e("fumen_2b", [
                E.e("difnum", s["2b_difnum"], __type: "u8"),
                E.e("playable", 1, __type: "u8")
              ]),
              E.e("fumen_2a", [
                E.e("difnum", s["2a_difnum"], __type: "u8"),
                E.e("playable", 1, __type: "u8")
              ])
            ])
          ],
          id: mid
        )
      end

    response =
      E.e(
        "response",
        E.e("game", [
          E.e("mdb", non_empty(music_nodes)),
          E.e(
            "extra",
            non_empty(
              for {mid, _s} <- songs do
                E.e("info", E.e("music_id", mid, __type: "s32"))
              end
            )
          ),
          E.e(
            "contest",
            for i <- 1..2 do
              E.e("info", [
                E.e("contest_id", i, __type: "s32"),
                E.e("start_date", 1_683_422_123_358, __type: "u64"),
                E.e("end_date", 1_693_422_123_358, __type: "u64"),
                E.e("title", "", __type: "str"),
                E.e("regulation", i, __type: "s32"),
                E.e(
                  "target_music",
                  E.e("music", [
                    E.e("music_id", 1, __type: "s32"),
                    E.e("music_type", "1b", __type: "str")
                  ])
                )
              ])
            end
          ),
          E.e(
            "event",
            for e <- 1..13 do
              E.e("info", [
                E.e("event_id", e, __type: "s32"),
                E.e("start_date", 1_683_422_123_358, __type: "u64"),
                E.e("end_date", 1_693_422_123_358, __type: "u64"),
                E.e("param", "", __type: "str")
              ])
            end
          )
          # E.kac2020(
          #     E.reward(
          #         E.data(
          #             E.music_id(1, __type="s32"),
          #             E.is_available(1, __type="bool"),
          #         )
          #     )
          # ),
          # E.silhouette(E.info(E.silhouette_id(i, __type="s32"))),
          # E.music_condition(*[E.music(E.conditions(), id=s) for s in songs]),
        ])
      )

    Core.send_response(conn, info, response)
  end

  def drs_game_get_playdata(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    dataid = Core.module_node(info) |> XNode.child("userid") |> XNode.child("refid") |> text()
    profile = get_game_profile(dataid, game_version)

    response =
      if profile != nil and profile != %{} do
        {djid, _djid_split} = get_id_from_profile(dataid)

        paramdata =
          for [data_type, data_id, param_list] <- profile["params"] do
            E.e("data", [
              E.e("data_type", data_type, __type: "s32"),
              E.e("data_id", data_id, __type: "s32"),
              E.e("param_list", param_list, __type: "s32")
            ])
          end

        E.e(
          "response",
          E.e("game", [
            E.e("result", 0, __type: "s32"),
            E.e("userid", E.e("code", djid, __type: "s32")),
            E.e("profile", E.e("name", profile["name"], __type: "str")),
            E.e("playinfo", [
              E.e("softcode", "", __type: "str"),
              E.e("start_date", 1_683_422_123_358, __type: "u64"),
              E.e("end_date", 1_683_422_123_358, __type: "u64"),
              E.e("mode_id", profile["mode_id"], __type: "s32"),
              E.e("music_id", profile["music_id"], __type: "s32"),
              E.e("music_type", profile["music_type"], __type: "str"),
              E.e("pcbid", "0", __type: "str"),
              E.e("locid", "EA000001", __type: "str")
            ]),
            E.e("paramdata", non_empty(paramdata)),
            E.e("dance_dance_rush", E.e("data")),
            E.e("summer_dance_damp", E.e("data")),
            E.e("kac2020"),
            E.e("hidden_param", 0, __type: "s32"),
            E.e("play_count", 1001, __type: "u32"),
            E.e("daily_count", 301, __type: "u32"),
            E.e("play_chain", 31, __type: "u32")
          ])
        )
      else
        E.e(
          "response",
          E.e(
            "game",
            E.e("result", 1, __type: "s32")
          )
        )
      end

    Core.send_response(conn, info, response)
  end

  def drs_game_lock_multi_login(conn) do
    {info, conn} = Core.process_request(conn)

    response = E.e("response", E.e("game"))

    Core.send_response(conn, info, response)
  end

  def drs_game_sign_up(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    root = Core.module_node(info)

    dataid = root |> XNode.child("userid") |> XNode.child("dataid") |> text()
    _cardno = root |> XNode.child("userid") |> XNode.child("cardno") |> text()
    name = root |> XNode.child("profile") |> XNode.child("name") |> text()

    all_profiles_for_card =
      DB.get("dancerush_profile", %{"card" => dataid}) || %{"card" => dataid, "version" => %{}}

    all_profiles_for_card =
      if Map.has_key?(all_profiles_for_card, "drs_id") do
        all_profiles_for_card
      else
        Map.put(all_profiles_for_card, "drs_id", :rand.uniform(90_000_000) + 9_999_999)
      end

    version = %{
      "game_version" => game_version,
      "name" => name,
      "mode_id" => 0,
      "music_id" => 1,
      "music_type" => "1a",
      "params" => []
    }

    all_profiles_for_card =
      put_in(all_profiles_for_card, ["version", to_string(game_version)], version)

    DB.upsert("dancerush_profile", all_profiles_for_card, %{"card" => dataid})

    response = E.e("response", E.e("game"))

    Core.send_response(conn, info, response)
  end

  def drs_game_get_musicscore(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    scores =
      for record <- DB.search("drs_scores_best", %{"game_version" => game_version}) do
        [
          record["music_id"],
          record["music_type"],
          record["score"],
          record["rank"],
          record["combo"],
          record["param"]
        ]
      end

    music_nodes =
      for [music_id, music_type, score, rank, combo, param] <- scores do
        E.e("music", [
          E.e("music_id", music_id, __type: "s32"),
          E.e("music_type", music_type, __type: "str"),
          E.e("play_cnt", 1, __type: "s32"),
          E.e("score", score, __type: "s32"),
          E.e("rank", rank, __type: "s32"),
          E.e("combo", combo, __type: "s32"),
          E.e("param", param, __type: "s32"),
          E.e("bestscore_date", 1_683_422_123_358, __type: "u64"),
          E.e("lastplay_date", 1_683_422_123_358, __type: "u64")
        ])
      end

    response =
      E.e(
        "response",
        E.e(
          "game",
          E.e("scoredata", non_empty(music_nodes))
        )
      )

    Core.send_response(conn, info, response)
  end

  def drs_save_musicscore(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    timestamp = :os.system_time(:millisecond) / 1000

    root = Core.module_node(info) |> first_child()

    dataid = root |> XNode.child("userid") |> XNode.child("refid") |> text()
    profile = get_game_profile(dataid, game_version)
    {djid, _djid_split} = get_id_from_profile(dataid)

    music_id = root |> XNode.child("music_id") |> text() |> int()
    music_type = root |> XNode.child("music_type") |> text()
    mode = root |> XNode.child("mode") |> text() |> int()
    score = root |> XNode.child("score") |> text() |> int()
    rank = root |> XNode.child("rank") |> text() |> int()
    combo = root |> XNode.child("combo") |> text() |> int()
    param = root |> XNode.child("param") |> text() |> int()
    perfect = root |> XNode.child("member") |> XNode.child("perfect") |> text() |> int()
    great = root |> XNode.child("member") |> XNode.child("great") |> text() |> int()
    good = root |> XNode.child("member") |> XNode.child("good") |> text() |> int()
    bad = root |> XNode.child("member") |> XNode.child("bad") |> text() |> int()

    attempt_doc = %{
      "timestamp" => timestamp,
      "game_version" => game_version,
      "drs_id" => djid,
      "music_id" => music_id,
      "music_type" => music_type,
      "mode" => mode,
      "score" => score,
      "rank" => rank,
      "combo" => combo,
      "param" => param,
      "perfect" => perfect,
      "great" => great,
      "good" => good,
      "bad" => bad
    }

    # The best key includes the game version and music_type (a string);
    # play_style carries both.
    case Scores.record_attempt(%{
           game: "drs",
           version: game_version,
           player: to_string(djid),
           song: music_id,
           chart: 0,
           play_style: "#{game_version}:#{music_type}",
           score: score,
           clear: 0,
           miss: nil,
           payload: %{
             "rank" => rank,
             "combo" => combo,
             "param" => param,
             "game_version" => game_version,
             "name" => profile["name"]
           },
           attempt: attempt_doc,
           stats: %{clear: false, fc: false},
           merge: Scores.Merge.spec("drs"),
           idempotency: %{
             key: Scores.derive_key("drs", "#{info.module}.#{info.method}", djid, info.text),
             scope: "#{info.module}.#{info.method}",
             payload_hash: Scores.hash_payload(info.text)
           },
           dual_write: fn _recorded ->
             dual_write_musicscore(
               attempt_doc,
               game_version,
               djid,
               profile["name"],
               music_id,
               music_type,
               score,
               rank,
               combo,
               param
             )
           end
         }) do
      {:ok, _recorded} ->
        Core.send_response(conn, info, E.e("response", E.e("game")))

      {:error, _reason} ->
        Core.reject_request(conn, info)
    end
  end

  # Project the recorded play into the legacy document tables, in the same
  # transaction. drs game read paths still use those; the relational
  # best_scores row lock serializes writers per player+chart.
  defp dual_write_musicscore(
         attempt_doc,
         game_version,
         djid,
         name,
         music_id,
         music_type,
         score,
         rank,
         combo,
         param
       ) do
    DB.insert("drs_scores", attempt_doc)

    best_conds = %{
      "drs_id" => djid,
      "game_version" => game_version,
      "music_id" => music_id,
      "music_type" => music_type
    }

    best = DB.get("drs_scores_best", best_conds) || %{}

    best_score_data = %{
      "game_version" => game_version,
      "drs_id" => djid,
      "name" => name,
      "music_id" => music_id,
      "music_type" => music_type,
      "score" => max(score, Map.get(best, "score", score)),
      "rank" => max(rank, Map.get(best, "rank", rank)),
      "combo" => max(combo, Map.get(best, "combo", combo)),
      "param" => param
    }

    DB.upsert("drs_scores_best", best_score_data, best_conds)
  end

  def drs_save_playdata(conn) do
    {info, conn} = Core.process_request(conn)
    game_version = info.game_version

    root = Core.module_node(info) |> first_child()

    dataid = root |> XNode.child("userid") |> XNode.child("refid") |> text()

    profile = get_profile(dataid)
    game_profile = get_in(profile || %{}, ["version", to_string(game_version)]) || %{}

    game_profile =
      Map.put(
        game_profile,
        "mode_id",
        root |> XNode.child("playinfo") |> XNode.child("mode_id") |> text() |> int()
      )

    game_profile =
      Map.put(
        game_profile,
        "music_id",
        root |> XNode.child("playinfo") |> XNode.child("music_id") |> text() |> int()
      )

    game_profile =
      Map.put(
        game_profile,
        "music_type",
        root |> XNode.child("playinfo") |> XNode.child("music_type") |> text()
      )

    old_params = Map.fetch!(game_profile, "params")

    params =
      Enum.reduce(old_params, {[], %{}}, fn [old_t, old_i, old_p], acc ->
        nested_put(acc, to_string(old_t), to_string(old_i), old_p)
      end)

    params =
      root
      |> XNode.child("paramdata")
      |> children()
      |> Enum.reduce(params, fn param_info, acc ->
        t = param_info |> XNode.child("data_type") |> text()
        i = param_info |> XNode.child("data_id") |> text()
        p = param_info |> XNode.child("param_list") |> XNode.text_ints()

        nested_put(acc, t, i, p)
      end)

    params_list =
      params
      |> nested_to_list()
      |> Enum.map(fn {t, i, p} -> [String.to_integer(t), String.to_integer(i), p] end)

    game_profile = Map.put(game_profile, "params", params_list)

    profile = put_in(profile, ["version", to_string(game_version)], game_profile)

    DB.upsert("dancerush_profile", profile, %{"card" => dataid})

    response = E.e("response", E.e("game"))

    Core.send_response(conn, info, response)
  end

  ## Helpers

  # Parse the first existing file of `paths` as XML. Returns the root XNode,
  # or nil when none of the paths exist (mirrors the Python
  # `for f in (...): if path.exists(f)` loop).
  defp load_xml(paths, encoding) do
    Enum.find_value(paths, fn f ->
      if File.exists?(f) do
        raw = File.read!(f)
        text = if encoding == :shift_jisx0213, do: BaconNet.CP932.decode(raw), else: raw
        Kbinxml.from_text(text).node
      end
    end)
  end

  # E.e/2 with an empty list would emit a `__count="0"` value node; the Python
  # ElementMaker produces an empty container element instead.
  defp non_empty([]), do: nil
  defp non_empty(list), do: list

  defp first_child(%XNode{children: [first | _]}), do: first

  defp children(%XNode{children: children}), do: children

  defp text(%XNode{text: text}), do: text

  defp int(text) when is_binary(text), do: text |> String.trim() |> String.to_integer()

  # Insertion-ordered nested string map {t => {i => p}}, mirroring the Python
  # dict-of-dicts used by the param merge loop: keys iterate in first
  # insertion order, values are overwritten in place. State is
  # {t_order, %{t => {i_order, %{i => p}}}}.
  defp nested_put({t_order, data}, t, i, p) do
    {t_order, {i_order, values}} =
      case Map.fetch(data, t) do
        :error -> {t_order ++ [t], {[], %{}}}
        {:ok, inner} -> {t_order, inner}
      end

    i_order = if Map.has_key?(values, i), do: i_order, else: i_order ++ [i]
    values = Map.put(values, i, p)

    {t_order, Map.put(data, t, {i_order, values})}
  end

  defp nested_to_list({t_order, data}) do
    Enum.flat_map(t_order, fn t ->
      {i_order, values} = Map.fetch!(data, t)

      Enum.map(i_order, fn i ->
        {t, i, Map.fetch!(values, i)}
      end)
    end)
  end
end
