defmodule BaconNet.MusicdataTool do
  @moduledoc """
  IIDX music_data.bin reader/writer, ported from utils/musicdata_tool.py.
  """

  alias BaconNet.CP932

  @handlers MapSet.new([20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 80])

  defstruct data: nil, rest: <<>>

  ## Reading

  defp read_string(bin, length, encoding \\ :cp932) do
    <<raw::binary-size(length), rest::binary>> = bin

    str =
      case encoding do
        :cp932 -> CP932.decode(raw)
        :utf16le -> decode_utf16le(raw)
      end

    {String.trim_trailing(str, <<0>>), rest}
  end

  # Python's decode("utf-16-le", errors="ignore"): invalid code units dropped.
  defp decode_utf16le(raw) do
    for <<unit::little-16 <- raw>>,
        unit < 0xD800 or unit > 0xDFFF,
        into: <<>>,
        do: <<unit::utf8>>
  end

  defp u32(bin), do: unpack(bin, 4)
  defp u16(bin), do: unpack(bin, 2)
  defp u8(bin), do: unpack(bin, 1)

  defp unpack(bin, size) do
    <<v::little-size(size)-unit(8), rest::binary>> = bin
    {v, rest}
  end

  defp s16(bin) do
    <<v::little-signed-16, rest::binary>> = bin
    {v, rest}
  end

  defp skip(bin, n) do
    <<_::binary-size(n), rest::binary>> = bin
    rest
  end

  def reader(version, bin, song_count) do
    {entries, _rest} =
      Enum.map_reduce(1..song_count//1, bin, fn _, bin ->
        read_entry(version, bin)
      end)

    entries
  end

  defp read_entry(version, bin) do
    {title, title_ascii, genre, artist, subtitle, bin} =
      if version >= 32 and version != 80 do
        {title, bin} = read_string(bin, 0x100, :utf16le)
        {title_ascii, bin} = read_string(bin, 0x40)
        {genre, bin} = read_string(bin, 0x80, :utf16le)
        {artist, bin} = read_string(bin, 0x100, :utf16le)
        {subtitle, bin} = read_string(bin, 0x100, :utf16le)
        {title, title_ascii, genre, artist, subtitle, bin}
      else
        {title, bin} = read_string(bin, 0x40)
        {title_ascii, bin} = read_string(bin, 0x40)
        {genre, bin} = read_string(bin, 0x40)
        {artist, bin} = read_string(bin, 0x40)
        {title, title_ascii, genre, artist, nil, bin}
      end

    {texture_title, bin} = u32(bin)
    {texture_artist, bin} = u32(bin)
    {texture_genre, bin} = u32(bin)
    {texture_load, bin} = u32(bin)
    {texture_list, bin} = u32(bin)

    {texture_subtitle, bin} =
      if version >= 32 and version != 80, do: u32(bin), else: {nil, bin}

    {font_idx, bin} = u32(bin)
    {game_version, bin} = u16(bin)

    {other_folder, bemani_folder, splittable_diff, extra_folders, bin} =
      if version >= 32 and version != 80 do
        {other_folder, bin} = u16(bin)
        {bemani_folder, bin} = u16(bin)
        {beginner_rec_folder, bin} = u16(bin)
        {iidx_rec_folder, bin} = u16(bin)
        {bemani_rec_folder, bin} = u16(bin)
        {splittable_diff, bin} = u16(bin)
        {unk_unused, bin} = u16(bin)

        {other_folder, bemani_folder, splittable_diff,
         %{
           "beginner_rec_folder" => beginner_rec_folder,
           "iidx_rec_folder" => iidx_rec_folder,
           "bemani_rec_folder" => bemani_rec_folder,
           "unk_unused" => unk_unused
         }, bin}
      else
        {other_folder, bin} = u16(bin)
        {bemani_folder, bin} = u16(bin)
        {splittable_diff, bin} = u16(bin)
        {other_folder, bemani_folder, splittable_diff, %{}, bin}
      end

    {levels, bin} =
      if version >= 27 do
        read_levels10(bin)
      else
        {spn, bin} = u8(bin)
        {sph, bin} = u8(bin)
        {spa, bin} = u8(bin)
        {dpn, bin} = u8(bin)
        {dph, bin} = u8(bin)
        {dpa, bin} = u8(bin)
        {spb, bin} = u8(bin)
        {dpb, bin} = u8(bin)
        {[spb, spn, sph, spa, 0, dpb, dpn, dph, dpa, 0], bin}
      end

    [spb_level, spn_level, sph_level, spa_level, spl_level,
     dpb_level, dpn_level, dph_level, dpa_level, dpl_level] = levels

    bin =
      cond do
        version == 80 -> skip(bin, 0x146)
        version >= 27 -> skip(bin, 0x286)
        true -> skip(bin, 0xA0)
      end

    {song_id, bin} = u32(bin)
    {volume, bin} = u32(bin)

    {idents, bin} =
      if version >= 27 do
        read_levels10(bin)
      else
        {spn, bin} = u8(bin)
        {sph, bin} = u8(bin)
        {spa, bin} = u8(bin)
        {dpn, bin} = u8(bin)
        {dph, bin} = u8(bin)
        {dpa, bin} = u8(bin)
        {spb, bin} = u8(bin)
        {dpb, bin} = u8(bin)
        {[spb, spn, sph, spa, 48, dpb, dpn, dph, dpa, 48], bin}
      end

    [spb_ident, spn_ident, sph_ident, spa_ident, spl_ident,
     dpb_ident, dpn_ident, dph_ident, dpa_ident, dpl_ident] = idents

    {bga_delay, bin} = s16(bin)

    bin = if version <= 26 or version == 80, do: skip(bin, 2), else: bin

    {bga_filename, bin} = read_string(bin, 0x20)

    bin = if version == 80, do: skip(bin, 2), else: bin

    {afp_flag, bin} = u32(bin)

    afp_count = if version >= 22, do: 10, else: 9

    {afp_data, bin} =
      Enum.map_reduce(1..afp_count//1, bin, fn _, acc ->
        read_string(acc, 0x20)
      end)

    bin = if version >= 26, do: skip(bin, 4), else: bin

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
      if version >= 32 and version != 80 do
        entry
        |> Map.put("subtitle", subtitle)
        |> Map.put("texture_subtitle", texture_subtitle)
        |> Map.merge(extra_folders)
      else
        entry
      end

    {entry, bin}
  end

  defp read_levels10(bin) do
    {vals, rest} =
      Enum.map_reduce(1..10//1, bin, fn _, acc -> u8(acc) end)

    {vals, rest}
  end

  ## Writing

  defp write_string(out, input, length, encoding \\ :cp932) do
    truncated = String.slice(input, 0, length)

    data =
      case encoding do
        :cp932 -> CP932.encode(truncated)
        :utf16le -> :unicode.characters_to_binary(truncated, :utf8, {:utf16, :little})
      end

    [out, data, :binary.copy(<<0>>, max(length - byte_size(data), 0))]
  end

  defp hex_pad(n, width) do
    n |> Integer.to_string() |> String.pad_leading(width, "0")
  end

  defp p32(v), do: <<v::little-32>>
  defp p16(v), do: <<v::little-16>>
  defp p8(v), do: <<v>>

  def writer(version, data) do
    cur_style_entries = version * 1000
    max_entries = cur_style_entries + 1000
    new_style = version >= 32 and version != 80

    exist_ids =
      data
      |> Enum.with_index()
      |> Map.new(fn {song, i} -> {song["song_id"], i} end)

    header =
      if version >= 32 do
        ["IIDX", p32(version), p16(length(data)), p16(0), p32(max_entries)]
      else
        ["IIDX", p32(version), p16(length(data)), p32(max_entries), p16(0)]
      end

    {index, _current_song} =
      Enum.map_reduce(0..(max_entries - 1)//1, 0, fn i, current_song ->
        cond do
          Map.has_key?(exist_ids, i) ->
            {entry_pack(new_style, current_song), current_song + 1}

          i >= cur_style_entries ->
            {entry_pack(new_style, 0), current_song}

          true ->
            {entry_pack(new_style, -1), current_song}
        end
      end)

    songs =
      for k <- exist_ids |> Map.keys() |> Enum.sort() do
        write_entry(version, Enum.at(data, exist_ids[k]))
      end

    IO.iodata_to_binary([header, index, songs])
  end

  defp entry_pack(true, v), do: <<v::little-signed-32>>
  defp entry_pack(false, v), do: <<v::little-signed-16>>

  defp write_entry(version, song_data) do
    new_style = version >= 32 and version != 80

    strings =
      if new_style do
        [
          write_string([], song_data["title"], 0x100, :utf16le),
          write_string([], song_data["title_ascii"], 0x40),
          write_string([], song_data["genre"], 0x80, :utf16le),
          write_string([], song_data["artist"], 0x100, :utf16le),
          write_string([], Map.get(song_data, "subtitle", ""), 0x100, :utf16le)
        ]
      else
        [
          write_string([], song_data["title"], 0x40),
          write_string([], song_data["title_ascii"], 0x40),
          write_string([], song_data["genre"], 0x40),
          write_string([], song_data["artist"], 0x40)
        ]
      end

    textures =
      [
        p32(song_data["texture_title"]),
        p32(song_data["texture_artist"]),
        p32(song_data["texture_genre"]),
        p32(song_data["texture_load"]),
        p32(song_data["texture_list"])
      ] ++ if new_style, do: [p32(Map.get(song_data, "texture_subtitle", 0))], else: []

    fonts = [p32(song_data["font_idx"]), p16(song_data["game_version"])]

    folders =
      if new_style do
        [
          p16(song_data["other_folder"]),
          p16(song_data["bemani_folder"]),
          p16(Map.get(song_data, "beginner_rec_folder", 0)),
          p16(Map.get(song_data, "iidx_rec_folder", 0)),
          p16(Map.get(song_data, "bemani_rec_folder", 0)),
          p16(song_data["splittable_diff"]),
          p16(Map.get(song_data, "unk_unused", 0))
        ]
      else
        [
          p16(song_data["other_folder"]),
          p16(song_data["bemani_folder"]),
          p16(song_data["splittable_diff"])
        ]
      end

    levels =
      if version >= 27 do
        for k <- ~w(SPB_level SPN_level SPH_level SPA_level SPL_level
                  DPB_level DPN_level DPH_level DPA_level DPL_level),
            do: p8(song_data[k])
      else
        for k <- ~w(SPN_level SPH_level SPA_level DPN_level DPH_level DPA_level
                  SPB_level DPB_level),
            do: p8(song_data[k])
      end

    unk_sect1 =
      cond do
        version == 80 ->
          Base.decode16!(
            hex_pad(1, 14) <> hex_pad(2, 8) <> hex_pad(3, 248) <> hex_pad(4, 8) <>
              hex_pad(3, 120) <> hex_pad(4, 8) <> hex_pad(0, 246)
          )

        version >= 32 ->
          Base.decode16!(hex_pad(0, 1292))

        version >= 27 ->
          Base.decode16!(
            hex_pad(1, 14) <> hex_pad(2, 8) <> hex_pad(3, 248) <> hex_pad(4, 8) <>
              hex_pad(0, 1014)
          )

        true ->
          Base.decode16!(hex_pad(0, 320))
      end

    idents =
      if version >= 27 do
        for k <- ~w(SPB_ident SPN_ident SPH_ident SPA_ident SPL_ident
                  DPB_ident DPN_ident DPH_ident DPA_ident DPL_ident),
            do: p8(song_data[k])
      else
        for k <- ~w(SPN_ident SPH_ident SPA_ident DPN_ident DPH_ident DPA_ident
                  SPB_ident DPB_ident),
            do: p8(song_data[k])
      end

    bga = [<<song_data["bga_delay"]::little-signed-16>>]
    unk2 = if version <= 26 or version == 80, do: [<<0, 0>>], else: []
    bga_filename = write_string([], song_data["bga_filename"], 0x20)
    unk3 = if version == 80, do: [<<0, 0>>], else: []
    afp_flag = p32(song_data["afp_flag"])

    afp_count = if version >= 22, do: 10, else: 9

    afp_data =
      for idx <- 0..(afp_count - 1)//1 do
        case Enum.at(song_data["afp_data"], idx) do
          nil -> write_string([], "", 0x20)
          s -> write_string([], s, 0x20)
        end
      end

    unk4 = if version >= 26, do: [<<0, 0, 0, 0>>], else: []

    [
      strings,
      textures,
      fonts,
      folders,
      levels,
      unk_sect1,
      p32(song_data["song_id"]),
      p32(song_data["volume"]),
      idents,
      bga,
      unk2,
      bga_filename,
      unk3,
      afp_flag,
      afp_data,
      unk4
    ]
  end

  ## File-level operations

  @doc "Parse a music_data.bin file. Returns %{\"data_ver\" => v, \"data\" => entries}."
  def extract_data(bin) do
    <<"IIDX", rest::binary>> = bin
    {version, rest} = u32(rest)
    new_style = version >= 32 and version != 80
    entry_size = if new_style, do: 4, else: 2

    {available_entries, total_entries, rest} =
      if version >= 32 do
        {avail, rest} = u16(rest)
        {_unk4, rest} = u16(rest)
        {total, rest} = u32(rest)
        {avail, total, rest}
      else
        {avail, rest} = u16(rest)
        {total, rest} = u32(rest)
        {_unk4, rest} = u16(rest)
        {avail, total, rest}
      end

    if MapSet.member?(@handlers, version) do
      # song index table (the reference only decodes it into dead data)
      rest = skip(rest, total_entries * entry_size)
      entries = reader(version, rest, available_entries)
      %{"data_ver" => version, "data" => entries}
    else
      raise "Couldn't find a handler for this data version"
    end
  end

  @doc "extract_file: parse a music_data.bin file (path) into JSON or a map."
  def extract_file(input, output \\ nil, in_memory \\ false) do
    bin = File.read!(input)

    unless binary_part(bin, 0, 4) == "IIDX" do
      raise "Input file (#{input}) is not valid"
    end

    result = extract_data(bin)

    unless in_memory do
      File.write!(output, Jason.encode!(result, pretty: true))
    end

    result
  end

  @doc "create_file: build a music_data.bin from a JSON extraction."
  def create_file(input, output, placeholder \\ nil) do
    data = input |> File.read!() |> Jason.decode!()
    version = Map.get(data, "data_ver", placeholder) || raise "Couldn't find data version"

    if MapSet.member?(@handlers, version) do
      File.write!(output, writer(version, data["data"]))
    else
      raise "Couldn't find a handler for this data version"
    end
  end

  @doc "merge_files: merge songs missing from basefile into it; optionally write a diff."
  def merge_files(input, basefile, output, diff \\ false) do
    old_data = extract_file(input, nil, true)
    new_data = extract_file(basefile, nil, true)

    new_song_ids = MapSet.new(new_data["data"], & &1["song_id"])
    merged_songs = Enum.reject(old_data["data"], &MapSet.member?(new_song_ids, &1["song_id"]))

    File.write!(output, writer(new_data["data_ver"], new_data["data"] ++ merged_songs))

    if diff do
      diff_path = binary_part(output, 0, byte_size(output) - 4) <> "_diff.bin"
      File.write!(diff_path, writer(new_data["data_ver"], merged_songs))
    end
  end
end
