defmodule BaconNet.Modules.Iidx.Api do
  @moduledoc "Port of modules/iidx/api.py."

  import Bitwise
  import Plug.Conn, only: [send_resp: 3]

  alias BaconNet.{Api, Card, CP932, DB, XNode}

  def routes do
    %{
      prefix: "/iidx",
      tag: "api_iidx",
      handlers: [],
      api: [
        {:get, ["profiles"], :iidx_profiles},
        {:get, ["profiles", :iidx_id], :iidx_profile_id},
        {:patch, ["profiles", :iidx_id], :iidx_profile_id_patch},
        {:patch, ["profiles", :iidx_id, :version], :iidx_profile_id_version_patch},
        {:get, ["card", :card], :iidx_card_to_profile},
        {:get, ["scores"], :iidx_scores},
        {:get, ["scores", :iidx_id], :iidx_scores_id},
        {:get, ["scores_best"], :iidx_scores_best},
        {:get, ["scores_best", :iidx_id], :iidx_scores_best_id},
        {:get, ["music_id", :music_id, "all"], :iidx_scores_id_music_all},
        {:get, ["music_id", :music_id, "best"], :iidx_scores_id_best},
        {:get, ["class_best", :iidx_id], :iidx_class_best},
        {:get, ["score_stats", "all"], :iidx_score_stats},
        {:get, ["score_stats", :music_id], :iidx_score_stats_song},
        {:post, ["parse_mdb", "upload"], :iidx_receive_mdb}
      ]
    }
  end

  # IIDX_Profile_Version_Items body field => game_profile key
  @version_item_fields [
    {"djname", "djname"},
    {"region", "region"},
    {"head", "head"},
    {"hair", "hair"},
    {"face", "face"},
    {"hand", "hand"},
    {"body", "body"},
    {"frame", "frame"},
    {"turntable", "turntable"},
    {"explosion", "explosion"},
    {"bgm", "bgm"},
    {"sudden", "sudden"},
    {"categoryvoice", "categoryvoice"},
    {"note", "note"},
    {"fullcombo", "fullcombo"},
    {"keybeam", "keybeam"},
    {"judgestring", "judgestring"},
    {"soundpreview", "soundpreview"},
    {"grapharea", "grapharea"},
    {"effector_lock", "effector_lock"},
    {"effector_type", "effector_type"},
    {"explosion_size", "explosion_size"},
    {"alternate_hcn", "alternate_hcn"},
    {"kokokara_start", "kokokara_start"},
    {"show_category_grade", "_show_category_grade"},
    {"show_category_status", "_show_category_status"},
    {"show_category_difficulty", "_show_category_difficulty"},
    {"show_category_alphabet", "_show_category_alphabet"},
    {"show_category_rival_play", "_show_category_rival_play"},
    {"show_category_rival_winlose", "_show_category_rival_winlose"},
    {"show_category_all_rival_play", "_show_category_all_rival_play"},
    {"show_category_arena_winlose", "_show_category_arena_winlose"},
    {"show_rival_shop_info", "_show_rival_shop_info"},
    {"hide_play_count", "_hide_play_count"},
    {"show_score_graph_cutin", "_show_score_graph_cutin"},
    {"hide_iidx_id", "_hide_iidx_id"},
    {"classic_hispeed", "_classic_hispeed"},
    {"beginner_option_swap", "_beginner_option_swap"},
    {"show_lamps_as_no_play_in_arena", "_show_lamps_as_no_play_in_arena"},
    {"skin_customize_flag_frame", "skin_customize_flag_frame"},
    {"skin_customize_flag_bgm", "skin_customize_flag_bgm"},
    {"skin_customize_flag_lane", "skin_customize_flag_lane"},
    {"sp_rival_1_iidx_id", "sp_rival_1_iidx_id"},
    {"sp_rival_2_iidx_id", "sp_rival_2_iidx_id"},
    {"sp_rival_3_iidx_id", "sp_rival_3_iidx_id"},
    {"sp_rival_4_iidx_id", "sp_rival_4_iidx_id"},
    {"sp_rival_5_iidx_id", "sp_rival_5_iidx_id"},
    {"sp_rival_6_iidx_id", "sp_rival_6_iidx_id"},
    {"dp_rival_1_iidx_id", "dp_rival_1_iidx_id"},
    {"dp_rival_2_iidx_id", "dp_rival_2_iidx_id"},
    {"dp_rival_3_iidx_id", "dp_rival_3_iidx_id"},
    {"dp_rival_4_iidx_id", "dp_rival_4_iidx_id"},
    {"dp_rival_5_iidx_id", "dp_rival_5_iidx_id"},
    {"dp_rival_6_iidx_id", "dp_rival_6_iidx_id"}
  ]

  def iidx_profiles(conn, _params) do
    Api.json(conn, DB.all("iidx_profile"))
  end

  def iidx_profile_id(conn, %{"iidx_id" => iidx_id}) do
    iidx_id = parse_iidx_id(iidx_id)
    Api.json(conn, DB.get("iidx_profile", %{"iidx_id" => iidx_id}))
  end

  def iidx_profile_id_patch(conn, %{"iidx_id" => iidx_id}) do
    iidx_id = parse_iidx_id(iidx_id)
    profile = DB.get("iidx_profile", %{"iidx_id" => iidx_id})
    body = conn.body_params

    profile =
      profile
      |> apply_if_present(body, "card", "card")
      |> apply_if_present(body, "pin", "pin")

    DB.upsert("iidx_profile", profile, %{"iidx_id" => iidx_id})
    send_resp(conn, 204, "")
  end

  def iidx_profile_id_version_patch(conn, %{"iidx_id" => iidx_id, "version" => version}) do
    with {version, ""} <- Integer.parse(version) do
      if version < 30 do
        # TODO: differentiate 18, 19, 20, 29, 30
        send_resp(conn, 406, "")
      else
        iidx_id = parse_iidx_id(iidx_id)
        profile = DB.get("iidx_profile", %{"iidx_id" => iidx_id})
        version_key = Integer.to_string(version)
        game_profile = Map.get(profile["version"], version_key, %{})

        game_profile =
          Enum.reduce(@version_item_fields, game_profile, fn {body_key, profile_key}, acc ->
            apply_if_present(acc, conn.body_params, body_key, profile_key)
          end)

        profile = put_in(profile, ["version", version_key], game_profile)
        DB.upsert("iidx_profile", profile, %{"iidx_id" => iidx_id})
        send_resp(conn, 204, "")
      end
    else
      _ -> send_resp(conn, 422, "")
    end
  end

  def iidx_card_to_profile(conn, %{"card" => card}) do
    card = String.upcase(card)

    lookalike = [{"I", "1"}, {"O", "0"}, {"Q", "0"}, {"V", "U"}]

    card =
      Enum.reduce(lookalike, card, fn {k, v}, acc -> String.replace(acc, k, v) end)

    uid =
      if String.starts_with?(card, "E004") or String.starts_with?(card, "012E") do
        uid =
          card
          |> :binary.bin_to_list()
          |> Enum.filter(&(&1 in ~c"0123456789ABCDEF"))
          |> IO.iodata_to_binary()

        _kid = Card.to_konami_id(uid)
        uid
      else
        valid = Card.valid_characters() |> :binary.bin_to_list()

        kid =
          card
          |> :binary.bin_to_list()
          |> Enum.filter(&(&1 in valid))
          |> IO.iodata_to_binary()

        Card.to_uid(kid)
      end

    Api.json(conn, DB.get("iidx_profile", %{"card" => uid}))
  end

  def iidx_scores(conn, _params) do
    Api.json(conn, DB.all("iidx_scores"))
  end

  def iidx_scores_id(conn, %{"iidx_id" => iidx_id}) do
    Api.json(conn, DB.search("iidx_scores", %{"iidx_id" => parse_iidx_id(iidx_id)}))
  end

  def iidx_scores_best(conn, _params) do
    Api.json(conn, DB.all("iidx_scores_best"))
  end

  def iidx_scores_best_id(conn, %{"iidx_id" => iidx_id}) do
    Api.json(conn, DB.search("iidx_scores_best", %{"iidx_id" => parse_iidx_id(iidx_id)}))
  end

  # The Python source names this handler iidx_scores_id too (shadowing the
  # /scores/{iidx_id} one); renamed here so the module compiles.
  def iidx_scores_id_music_all(conn, %{"music_id" => music_id}) do
    with_int_param(conn, music_id, fn music_id ->
      Api.json(conn, DB.search("iidx_scores", %{"music_id" => music_id}))
    end)
  end

  def iidx_scores_id_best(conn, %{"music_id" => music_id}) do
    with_int_param(conn, music_id, fn music_id ->
      Api.json(conn, DB.search("iidx_scores_best", %{"music_id" => music_id}))
    end)
  end

  def iidx_class_best(conn, %{"iidx_id" => iidx_id}) do
    Api.json(conn, DB.search("iidx_class_best", %{"iidx_id" => parse_iidx_id(iidx_id)}))
  end

  def iidx_score_stats(conn, _params) do
    Api.json(conn, DB.all("iidx_score_stats"))
  end

  def iidx_score_stats_song(conn, %{"music_id" => music_id}) do
    with_int_param(conn, music_id, fn music_id ->
      Api.json(conn, DB.search("iidx_score_stats", %{"music_id" => music_id}))
    end)
  end

  def iidx_receive_mdb(conn, _params) do
    case conn.body_params do
      %{"file" => %Plug.Upload{path: path}} ->
        data = File.read!(path)
        do_receive_mdb(conn, data)

      _ ->
        send_resp(conn, 422, "")
    end
  end

  ## Internals

  # int("".join([i for i in iidx_id if i.isnumeric()]))
  defp parse_iidx_id(iidx_id) do
    iidx_id |> String.replace(~r/[^0-9]/, "") |> String.to_integer()
  end

  # FastAPI `x: int` path params: unparseable values are a 422 there.
  defp with_int_param(conn, value, fun) do
    case Integer.parse(value) do
      {int, ""} -> fun.(int)
      _ -> send_resp(conn, 422, "")
    end
  end

  defp apply_if_present(map, body, body_key, profile_key) do
    case Map.fetch(body, body_key) do
      {:ok, value} -> Map.put(map, profile_key, value)
      :error -> map
    end
  end

  defp do_receive_mdb(conn, data) do
    iidx_bin = Path.join("webui", "music_data.bin")
    iidx_vid = Path.join("webui", "video_music_list.xml")
    iidx_metadata = Path.join("webui", "iidx.json")

    conn =
      if binary_part(data, 0, min(byte_size(data), 4)) == "IIDX" do
        # data_ver = int.from_bytes(data[4:8], "little")
        File.write!(iidx_bin, data)

        try do
          extract_file(iidx_bin, iidx_metadata)
          send_resp(conn, 201, "")
        rescue
          e ->
            IO.inspect(e)
            send_resp(conn, 422, "")
        end
      else
        # video_music_list.xml to fix broken characters in title/artist
        # (this should be a separate route)
        try do
          music_data = iidx_metadata |> File.read!() |> Jason.decode!()
          File.write!(iidx_vid, data)
          proper_names = parse_video_music_list(iidx_vid)

          entries =
            Enum.map(music_data["data"], fn m ->
              mid = m["song_id"]

              case Map.fetch(proper_names, mid) do
                :error ->
                  m

                {:ok, names} ->
                  m =
                    if names["title"] != m["title"],
                      do: Map.put(m, "title", names["title"]),
                      else: m

                  if names["artist"] != m["artist"],
                    do: Map.put(m, "artist", names["artist"]),
                    else: m
              end
            end)

          music_data = Map.put(music_data, "data", entries)
          File.write!(iidx_metadata, Jason.encode!(music_data, pretty: [indent: "    "]))
          send_resp(conn, 201, "")
        rescue
          e ->
            IO.inspect(e)
            send_resp(conn, 422, "")
        catch
          kind, reason ->
            IO.inspect({kind, reason})
            send_resp(conn, 422, "")
        end
      end

    # Python's trailing `return Response(status_code=406)` is unreachable:
    # both branches above always return a response.
    conn
  end

  # proper_names: %{music_id (int) => %{"title" => _, "artist" => _}}
  defp parse_video_music_list(path) do
    {doc, _} =
      path
      |> File.read!()
      |> :binary.bin_to_list()
      |> :xmerl_scan.string(quiet: true, space: :preserve, encoding: :"utf-8")

    root = xml_to_xnode(doc)

    for entry <- root.children, into: %{} do
      mid = entry |> XNode.attr("id") |> String.to_integer()
      info = XNode.child(entry, "info")

      {mid,
       %{
         "title" => info |> XNode.child("title_name") |> Map.get(:text),
         "artist" => info |> XNode.child("artist_name") |> Map.get(:text)
       }}
    end
  end

  # xmerl record field positions (xmerl.hrl, stable across OTP versions):
  # xmlElement: 1=name, 7=attributes, 8=content
  # xmlAttribute: 1=name, 8=value
  # xmlText: 4=value
  # Unlike Kbinxml.from_text this keeps text untrimmed, like ElementTree .text.
  defp xml_to_xnode(elem) do
    tag = elem |> elem(1) |> to_string()

    attrs =
      elem
      |> elem(7)
      |> Enum.map(fn a -> {a |> elem(1) |> to_string(), a |> elem(8) |> List.to_string()} end)
      |> Enum.sort_by(&elem(&1, 0))

    content = elem(elem, 8)
    children = for c <- content, is_tuple(c) and elem(c, 0) == :xmlElement, do: xml_to_xnode(c)

    text =
      content
      |> Enum.filter(&(is_tuple(&1) and elem(&1, 0) == :xmlText))
      |> Enum.map_join(fn t -> t |> elem(4) |> List.to_string() end)

    %XNode{tag: tag, attrs: attrs, children: children, text: if(text == "", do: nil, else: text)}
  end

  ## music_data.bin extraction (utils/musicdata_tool.py extract_file/reader)

  # TRICORO .. SPARKLE SHOWER + next style, INFINITAS
  @data_versions [20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 80]

  defp extract_file(input, output) do
    bin = File.read!(input)

    if binary_part(bin, 0, min(byte_size(bin), 4)) != "IIDX" do
      # Python raises SystemExit here, which `except Exception` does not catch.
      exit("Input file (#{input}) is not valid")
    end

    <<_magic::binary-size(4), version::little-32, rest::binary>> = bin
    index_entry_size = if version >= 32 and version != 80, do: 4, else: 2

    {available_entries, total_entries, rest} =
      if version >= 32 do
        <<avail::little-16, _unk4::little-16, total::little-32, r::binary>> = rest
        {avail, total, r}
      else
        <<avail::little-16, total::little-32, _unk4::little-16, r::binary>> = rest
        {avail, total, r}
      end

    # The existing_song_ids index Python builds here is never used
    # afterwards; only advancing the read position matters.
    rest = skip_bytes(rest, index_entry_size * total_entries)

    if version in @data_versions do
      {entries, _rest} = read_song_entries(version, rest, available_entries, [])
      output_data = %{"data_ver" => version, "data" => entries}
      File.write!(output, Jason.encode!(output_data, pretty: [indent: "    "]))
      []
    else
      # Python raises SystemExit here as well (uncaught -> 500).
      exit("Couldn't find a handler for this data version")
    end
  end

  defp skip_bytes(bin, n), do: binary_part(bin, n, byte_size(bin) - n)

  defp read_song_entries(_version, rest, 0, acc), do: {Enum.reverse(acc), rest}

  defp read_song_entries(version, rest, count, acc) when count > 0 do
    {entry, rest} = read_song_entry(version, rest)
    read_song_entries(version, rest, count - 1, [entry | acc])
  end

  defp read_song_entry(version, bin) do
    wide = version >= 32 and version != 80

    {title, title_ascii, genre, artist, subtitle, bin} =
      if wide do
        {title, bin} = read_string(bin, 0x100, :utf16le)
        {title_ascii, bin} = read_string(bin, 0x40, :cp932)
        {genre, bin} = read_string(bin, 0x80, :utf16le)
        {artist, bin} = read_string(bin, 0x100, :utf16le)
        {subtitle, bin} = read_string(bin, 0x100, :utf16le)
        {title, title_ascii, genre, artist, subtitle, bin}
      else
        {title, bin} = read_string(bin, 0x40, :cp932)
        {title_ascii, bin} = read_string(bin, 0x40, :cp932)
        {genre, bin} = read_string(bin, 0x40, :cp932)
        {artist, bin} = read_string(bin, 0x40, :cp932)
        {title, title_ascii, genre, artist, nil, bin}
      end

    <<texture_title::little-32, texture_artist::little-32, texture_genre::little-32,
      texture_load::little-32, texture_list::little-32, bin::binary>> = bin

    {texture_subtitle, bin} =
      if wide do
        <<value::little-32, r::binary>> = bin
        {value, r}
      else
        {nil, bin}
      end

    <<font_idx::little-32, game_version::little-16, bin::binary>> = bin

    {other_folder, bemani_folder, beginner_rec_folder, iidx_rec_folder, bemani_rec_folder,
     splittable_diff, unk_unused,
     bin} =
      if wide do
        <<other::little-16, bemani::little-16, beginner_rec::little-16, iidx_rec::little-16,
          bemani_rec::little-16, splittable::little-16, unk::little-16, r::binary>> = bin

        {other, bemani, beginner_rec, iidx_rec, bemani_rec, splittable, unk, r}
      else
        <<other::little-16, bemani::little-16, splittable::little-16, r::binary>> = bin
        {other, bemani, nil, nil, nil, splittable, nil, r}
      end

    {spb_level, spn_level, sph_level, spa_level, spl_level, dpb_level, dpn_level, dph_level,
     dpa_level, dpl_level,
     bin} =
      if version >= 27 do
        <<spb, spn, sph, spa, spl, dpb, dpn, dph, dpa, dpl, r::binary>> = bin
        {spb, spn, sph, spa, spl, dpb, dpn, dph, dpa, dpl, r}
      else
        <<spn, sph, spa, dpn, dph, dpa, spb, dpb, r::binary>> = bin
        {spb, spn, sph, spa, 0, dpb, dpn, dph, dpa, 0, r}
      end

    unk_sect1_size =
      cond do
        version == 80 -> 0x146
        version >= 27 -> 0x286
        true -> 0xA0
      end

    <<_unk_sect1::binary-size(unk_sect1_size), bin::binary>> = bin

    <<song_id::little-32, volume::little-32, bin::binary>> = bin

    {spb_ident, spn_ident, sph_ident, spa_ident, spl_ident, dpb_ident, dpn_ident, dph_ident,
     dpa_ident, dpl_ident,
     bin} =
      if version >= 27 do
        <<spb, spn, sph, spa, spl, dpb, dpn, dph, dpa, dpl, r::binary>> = bin
        {spb, spn, sph, spa, spl, dpb, dpn, dph, dpa, dpl, r}
      else
        <<spn, sph, spa, dpn, dph, dpa, spb, dpb, r::binary>> = bin
        {spb, spn, sph, spa, 48, dpb, dpn, dph, dpa, 48, r}
      end

    <<bga_delay::little-signed-16, bin::binary>> = bin

    bin =
      if version <= 26 or version == 80 do
        <<_unk_sect2::binary-size(2), r::binary>> = bin
        r
      else
        bin
      end

    {bga_filename, bin} = read_string(bin, 0x20, :cp932)

    bin =
      if version == 80 do
        <<_unk_sect3::binary-size(2), r::binary>> = bin
        r
      else
        bin
      end

    <<afp_flag::little-32, bin::binary>> = bin

    afp_count = if version >= 22, do: 10, else: 9

    {afp_data, bin} =
      Enum.map_reduce(1..afp_count, bin, fn _, acc -> read_string(acc, 0x20, :cp932) end)

    bin =
      if version >= 26 do
        <<_unk_sect4::binary-size(4), r::binary>> = bin
        r
      else
        bin
      end

    entry = %{
      "song_id" => song_id,
      "title" => title,
      "title_ascii" => title_ascii,
      "genre" => genre,
      "artist" => artist,
      "texture_title" => texture_title,
      "texture_artist" => texture_artist,
      "texture_genre" => texture_genre,
      "texture_load" => texture_load,
      "texture_list" => texture_list,
      "font_idx" => font_idx,
      "game_version" => game_version,
      "other_folder" => other_folder,
      "bemani_folder" => bemani_folder,
      "splittable_diff" => splittable_diff,
      "SPB_level" => spb_level,
      "SPN_level" => spn_level,
      "SPH_level" => sph_level,
      "SPA_level" => spa_level,
      "SPL_level" => spl_level,
      "DPB_level" => dpb_level,
      "DPN_level" => dpn_level,
      "DPH_level" => dph_level,
      "DPA_level" => dpa_level,
      "DPL_level" => dpl_level,
      "volume" => volume,
      "SPB_ident" => spb_ident,
      "SPN_ident" => spn_ident,
      "SPH_ident" => sph_ident,
      "SPA_ident" => spa_ident,
      "SPL_ident" => spl_ident,
      "DPB_ident" => dpb_ident,
      "DPN_ident" => dpn_ident,
      "DPH_ident" => dph_ident,
      "DPA_ident" => dpa_ident,
      "DPL_ident" => dpl_ident,
      "bga_filename" => bga_filename,
      "bga_delay" => bga_delay,
      "afp_flag" => afp_flag,
      "afp_data" => afp_data
    }

    entry =
      if wide do
        Map.merge(entry, %{
          "subtitle" => subtitle,
          "texture_subtitle" => texture_subtitle,
          "beginner_rec_folder" => beginner_rec_folder,
          "iidx_rec_folder" => iidx_rec_folder,
          "bemani_rec_folder" => bemani_rec_folder,
          "unk_unused" => unk_unused
        })
      else
        entry
      end

    {entry, bin}
  end

  # utils/musicdata_tool.py read_string: fixed-length field, decode, rstrip NULs
  defp read_string(bin, length, encoding) do
    <<raw::binary-size(length), rest::binary>> = bin

    text =
      case encoding do
        :cp932 -> raw |> trim_trailing_nul_bytes() |> CP932.decode()
        :utf16le -> raw |> decode_utf16le_ignore() |> String.trim_trailing("\0")
      end

    {text, rest}
  end

  defp trim_trailing_nul_bytes(bin), do: trim_trailing_nul_bytes(bin, byte_size(bin))

  defp trim_trailing_nul_bytes(_bin, 0), do: ""

  defp trim_trailing_nul_bytes(bin, n) do
    if :binary.at(bin, n - 1) == 0,
      do: trim_trailing_nul_bytes(bin, n - 1),
      else: binary_part(bin, 0, n)
  end

  # utf-16-le decode with errors="ignore": lone surrogates are dropped
  defp decode_utf16le_ignore(bin) do
    units = for <<u::little-16 <- bin>>, do: u
    utf16_units_to_utf8(units, [])
  end

  defp utf16_units_to_utf8([], acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp utf16_units_to_utf8([u | rest], acc) when u >= 0xD800 and u <= 0xDBFF do
    case rest do
      [u2 | rest2] when u2 >= 0xDC00 and u2 <= 0xDFFF ->
        cp = 0x10000 + ((u - 0xD800) <<< 10) + (u2 - 0xDC00)
        utf16_units_to_utf8(rest2, [<<cp::utf8>> | acc])

      _ ->
        utf16_units_to_utf8(rest, acc)
    end
  end

  defp utf16_units_to_utf8([u | rest], acc) when u >= 0xDC00 and u <= 0xDFFF do
    utf16_units_to_utf8(rest, acc)
  end

  defp utf16_units_to_utf8([u | rest], acc) do
    utf16_units_to_utf8(rest, [<<u::utf8>> | acc])
  end
end
