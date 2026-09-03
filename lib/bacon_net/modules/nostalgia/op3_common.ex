defmodule BaconNet.Modules.Nostalgia.Op3Common do
  @moduledoc false

  alias BaconNet.{CP932, Core, E, Kbinxml, XNode}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"op3_common", "get_common_info", :op3_common_get_common_info},
        {"op3_common", "get_music_info", :op3_common_get_music_info}
      ]
    }
  end

  @song_attrs [
    "priority",
    "category_flag",
    "primary_category",
    "level_normal",
    "level_hard",
    "level_extreme",
    "level_real",
    "demo_popular",
    "demo_bemani",
    "destination_j",
    "destination_a",
    "destination_y",
    "destination_k",
    "offline",
    "unlock_type",
    "volume_bgm",
    "volume_key",
    "jk_jpn",
    "jk_asia",
    "jk_kor",
    "jk_idn",
    "real_unlock_type",
    "real_once_price",
    "real_forever_price"
  ]

  def op3_common_get_common_info(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e(
        "response",
        E.e("get_common_info", E.e("olupdate", E.e("delete_flag", 0, __type: "bool")))
      )

    Core.send_response(conn, info, response)
  end

  def op3_common_get_music_info(conn) do
    {info, conn} = Core.process_request(conn)

    revision = "21261"
    release_code = "2021090800"

    {revision, release_code, songs} =
      case load_xml(["modules/nostalgia/music_list.xml", "music_list.xml"], :shift_jisx0213) do
        nil ->
          {revision, release_code, []}

        root ->
          revision = XNode.attr(root, "revision")
          release_code = XNode.attr(root, "release_code")

          songs =
            Enum.map(root.children, fn entry ->
              mid = XNode.attr(entry, "index")

              attrs =
                Map.new(@song_attrs, fn atr ->
                  {atr, entry |> XNode.child(atr) |> text()}
                end)

              {mid, attrs}
            end)

          {revision, release_code, songs}
      end

    flags = List.duplicate(-1, 32)

    response =
      E.e(
        "response",
        E.e("get_music_info", [
          E.e(
            "music_list",
            non_empty(
              for {mid, s} <- songs do
                E.e(
                  "music_spec",
                  [
                    E.e("basename", "", __type: "str"),
                    E.e("title", "", __type: "str"),
                    E.e("title_kana", "", __type: "str"),
                    E.e("artist", "", __type: "str"),
                    E.e("artist_kana", "", __type: "str"),
                    E.e("license", "", __type: "str"),
                    E.e("license_site", "", __type: "str"),
                    E.e("priority", s["priority"], __type: "s8"),
                    E.e("category_flag", s["category_flag"], __type: "s32"),
                    E.e("primary_category", s["primary_category"], __type: "s8"),
                    E.e("level_normal", s["level_normal"], __type: "s8"),
                    E.e("level_hard", s["level_hard"], __type: "s8"),
                    E.e("level_extreme", s["level_extreme"], __type: "s8"),
                    E.e("level_real", s["level_real"], __type: "s8"),
                    E.e("demo_popular", s["demo_popular"], __type: "bool"),
                    E.e("demo_bemani", s["demo_bemani"], __type: "bool"),
                    E.e("destination_j", s["destination_j"], __type: "bool"),
                    E.e("destination_a", s["destination_a"], __type: "bool"),
                    E.e("destination_y", s["destination_y"], __type: "bool"),
                    E.e("destination_k", s["destination_k"], __type: "bool"),
                    E.e("offline", s["offline"], __type: "bool"),
                    E.e("unlock_type", s["unlock_type"], __type: "s8"),
                    E.e("volume_bgm", s["volume_bgm"], __type: "s8"),
                    E.e("volume_key", s["volume_key"], __type: "s8"),
                    E.e("start_date", "2017-03-01 10:00", __type: "str"),
                    E.e("end_date", "9999-12-31 23:59", __type: "str"),
                    E.e("expiration_date", "9999-12-31 23:59", __type: "str"),
                    E.e("description", "", __type: "str")
                  ],
                  index: mid
                )
              end
            ),
            revision: revision,
            release_code: release_code
          ),
          E.e(
            "overwrite_music_list",
            non_empty(
              for {mid, s} <- songs do
                E.e(
                  "music_spec",
                  [
                    E.e("jk_jpn", s["jk_jpn"], __type: "bool"),
                    E.e("jk_asia", s["jk_asia"], __type: "bool"),
                    E.e("jk_kor", s["jk_kor"], __type: "bool"),
                    E.e("jk_idn", s["jk_idn"], __type: "bool"),
                    E.e("unlock_type", s["unlock_type"], __type: "s8"),
                    E.e("real_unlock_type", s["real_unlock_type"], __type: "s8"),
                    E.e("start_date", "2017-03-01 10:00", __type: "str"),
                    E.e("end_date", "9999-12-31 23:59", __type: "str"),
                    E.e("real_once_price", s["real_once_price"], __type: "s32"),
                    E.e("real_forever_price", s["real_forever_price"], __type: "s32"),
                    E.e("real_start_date", "2017-03-01 10:00", __type: "str"),
                    E.e("real_end_date", "9999-12-31 23:59", __type: "str")
                  ],
                  index: mid
                )
              end
            ),
            revision: revision,
            release_code: release_code
          ),
          E.e("permitted_list", [
            E.e("flag", flags, __type: "s32", sheet_type: "0"),
            E.e("flag", flags, __type: "s32", sheet_type: "1"),
            E.e("flag", flags, __type: "s32", sheet_type: "2"),
            E.e("flag", flags, __type: "s32", sheet_type: "3")
          ]),
          E.e("gamedata_flag_list"),
          E.e("trend_music_list", E.e("trend_music", music_index: 1, rank: 1))
        ])
      )

    Core.send_response(conn, info, response)
  end

  ## Helpers

  # Parse the first existing file of `paths` as XML, decoding shift_jisx0213
  # through the cp932 table. Returns the root XNode, or nil when none of the
  # paths exist (mirrors the Python `for f in (...): if path.exists(f)` loop).
  defp load_xml(paths, encoding) do
    Enum.find_value(paths, fn f ->
      if File.exists?(f) do
        raw = File.read!(f)
        text = if encoding == :shift_jisx0213, do: CP932.decode(raw), else: raw
        Kbinxml.from_text(text).node
      end
    end)
  end

  # E.e/2 with an empty list would emit a `__count="0"` value node; the Python
  # ElementMaker produces an empty container element instead.
  defp non_empty([]), do: nil
  defp non_empty(list), do: list

  defp text(%XNode{text: text}), do: text
end
