defmodule BaconNet.Modules.Ddr.Api do
  @moduledoc "Port of modules/ddr/api.py (DDR JSON web API)."

  import Plug.Conn

  alias BaconNet.{Api, Card, DB, LZ77}

  def routes do
    %{
      prefix: "/ddr",
      tag: "api_ddr",
      handlers: [],
      api: [
        {:get, ["profiles"], :ddr_profiles},
        {:get, ["profiles", :ddr_id], :ddr_profile_id},
        {:patch, ["profiles", :ddr_id], :ddr_profile_id_patch},
        {:patch, ["profiles", :ddr_id, "19"], :ddr_profile_id_19_patch},
        {:patch, ["profiles", :ddr_id, "20"], :ddr_profile_id_20_patch},
        {:get, ["card", :card], :ddr_card_to_profile},
        {:get, ["scores"], :ddr_scores},
        {:get, ["scores", :ddr_id], :ddr_scores_id},
        {:get, ["scores_best"], :ddr_scores_best},
        {:get, ["scores_best", :ddr_id], :ddr_scores_best_id},
        {:get, ["mcode", :mcode, "all"], :ddr_scores_id_mcode_all},
        {:get, ["mcode", :mcode, "best"], :ddr_scores_id_best_mcode},
        {:post, ["parse_mdb", "upload"], :ddr_receive_mdb}
      ]
    }
  end

  @mdb_attributes [
    "basename",
    "title",
    "title_yomi",
    "artist",
    "bpmmin",
    "bpmmax",
    "series",
    "eventno",
    "bemaniflag",
    "bgstage",
    "movie",
    "genreflag",
    "voice"
  ]

  def ddr_profiles(conn, _params) do
    Api.json(conn, ordered_docs("ddr_profile"))
  end

  def ddr_profile_id(conn, %{"ddr_id" => ddr_id}) do
    Api.json(conn, DB.get("ddr_profile", %{"ddr_id" => numeric_id(ddr_id)}))
  end

  def ddr_profile_id_patch(conn, %{"ddr_id" => ddr_id}) do
    item = conn.body_params
    id = numeric_id(ddr_id)
    profile = DB.get("ddr_profile", %{"ddr_id" => id})

    profile =
      profile
      |> Map.put("card", Map.get(item, "card"))
      |> Map.put("pin", Map.get(item, "pin"))

    DB.upsert("ddr_profile", profile, %{"ddr_id" => id})

    send_resp(conn, 204, "")
  end

  def ddr_profile_id_19_patch(conn, %{"ddr_id" => ddr_id}) do
    item = conn.body_params
    id = numeric_id(ddr_id)
    profile = DB.get("ddr_profile", %{"ddr_id" => id})
    version = Map.fetch!(profile, "version")
    game_profile = Map.get(version, "19", %{})

    game_profile =
      game_profile
      |> Map.put("game_version", Map.get(item, "game_version"))
      |> Map.put("calories_disp", if(Map.get(item, "calories_disp"), do: "On", else: "Off"))
      |> Map.put("character", Map.get(item, "character"))
      |> Map.put("arrow_skin", Map.get(item, "arrow_skin"))
      |> Map.put("filter", Map.get(item, "filter"))
      |> Map.put("guideline", Map.get(item, "guideline"))
      |> Map.put("priority", Map.get(item, "priority"))
      |> Map.put("timing_disp", if(Map.get(item, "timing_disp"), do: "On", else: "Off"))
      |> Map.put("common", Map.get(item, "common"))
      |> Map.put("option", Map.get(item, "option"))
      |> Map.put("last", Map.get(item, "last"))
      |> Map.put("rival", Map.get(item, "rival"))
      |> Map.put("rival_1_ddr_id", Map.get(item, "rival_1_ddr_id"))
      |> Map.put("rival_2_ddr_id", Map.get(item, "rival_2_ddr_id"))
      |> Map.put("rival_3_ddr_id", Map.get(item, "rival_3_ddr_id"))

    profile = Map.put(profile, "version", Map.put(version, "19", game_profile))
    DB.upsert("ddr_profile", profile, %{"ddr_id" => id})

    send_resp(conn, 204, "")
  end

  def ddr_profile_id_20_patch(conn, %{"ddr_id" => ddr_id}) do
    item = conn.body_params
    id = numeric_id(ddr_id)
    profile = DB.get("ddr_profile", %{"ddr_id" => id})
    version = Map.fetch!(profile, "version")
    game_profile = Map.get(version, "20", %{})

    game_profile =
      game_profile
      |> Map.put("game_version", Map.get(item, "game_version"))
      |> Map.put("common_dancername", Map.get(item, "common_dancername"))
      |> Map.put("common_area", Map.get(item, "common_area"))
      |> Map.put("rival_1_ddr_id", Map.get(item, "rival_1_ddr_id"))
      |> Map.put("rival_2_ddr_id", Map.get(item, "rival_2_ddr_id"))
      |> Map.put("rival_3_ddr_id", Map.get(item, "rival_3_ddr_id"))
      |> Map.put("customize", Map.get(item, "customize"))

    profile = Map.put(profile, "version", Map.put(version, "20", game_profile))
    DB.upsert("ddr_profile", profile, %{"ddr_id" => id})

    send_resp(conn, 204, "")
  end

  def ddr_card_to_profile(conn, %{"card" => card}) do
    card = String.upcase(card)

    card =
      card
      |> String.replace("I", "1")
      |> String.replace("O", "0")
      |> String.replace("Q", "0")
      |> String.replace("V", "U")

    uid =
      if String.starts_with?(card, "E004") or String.starts_with?(card, "012E") do
        card
        |> :binary.bin_to_list()
        |> Enum.filter(&(&1 in ~c"0123456789ABCDEF"))
        |> IO.iodata_to_binary()
      else
        kid =
          card
          |> :binary.bin_to_list()
          |> Enum.filter(&(&1 in :binary.bin_to_list(Card.valid_characters())))
          |> IO.iodata_to_binary()

        Card.to_uid(kid)
      end

    Api.json(conn, DB.get("ddr_profile", %{"card" => uid}))
  end

  def ddr_scores(conn, _params) do
    Api.json(conn, ordered_docs("ddr_scores"))
  end

  def ddr_scores_id(conn, %{"ddr_id" => ddr_id}) do
    Api.json(conn, search_docs("ddr_scores", %{"ddr_id" => numeric_id(ddr_id)}))
  end

  def ddr_scores_best(conn, _params) do
    Api.json(conn, ordered_docs("ddr_scores_best"))
  end

  def ddr_scores_best_id(conn, %{"ddr_id" => ddr_id}) do
    Api.json(conn, search_docs("ddr_scores_best", %{"ddr_id" => numeric_id(ddr_id)}))
  end

  def ddr_scores_id_mcode_all(conn, %{"mcode" => mcode}) do
    Api.json(conn, search_docs("ddr_scores", %{"mcode" => String.to_integer(mcode)}))
  end

  def ddr_scores_id_best_mcode(conn, %{"mcode" => mcode}) do
    Api.json(conn, search_docs("ddr_scores_best", %{"mcode" => String.to_integer(mcode)}))
  end

  def ddr_receive_mdb(conn, _params) do
    with %Plug.Upload{path: path} <- conn.body_params["file"],
         {:ok, data} <- File.read(path),
         {:ok, xml} <- arc_read(data, arc_parse(data), "data/gamedata/musicdb.xml") do
      mdb = parse_musicdb(xml)

      ddr_metadata = Path.join("webui", "ddr.json")

      mdb =
        if File.exists?(ddr_metadata) do
          mdb_old = ddr_metadata |> File.read!() |> Jason.decode!()
          Map.merge(mdb, mdb_old)
        else
          mdb
        end

      File.write!(ddr_metadata, Jason.encode!(mdb, pretty: true))

      send_resp(conn, 201, "")
    else
      _ -> send_resp(conn, 406, "")
    end
  end

  ## ARC archive reader
  # https://github.com/DragonMinded/bemaniutils/blob/trunk/bemani/format/arc.py

  defp arc_parse(data) do
    case data do
      <<0x20, 0x11, 0x75, 0x19, _::little-32, numfiles::little-32, _::little-32, _::binary>> ->
        for fno <- 0..(numfiles - 1)//1, into: %{} do
          start = 16 + 16 * fno

          <<_::binary-size(start), nameoffset::little-32, fileoffset::little-32,
            uncompressedsize::little-32, compressedsize::little-32, _::binary>> = data

          {read_cstr(data, nameoffset), {fileoffset, uncompressedsize, compressedsize}}
        end

      _ ->
        # Python: bad magic -> __parse_file returns early leaving zero files,
        # so the later read_file raises KeyError (-> 406)
        %{}
    end
  end

  defp arc_read(data, files, filename) do
    case Map.fetch(files, filename) do
      :error ->
        # Python KeyError -> 406
        :error

      {:ok, {fileoffset, uncompressedsize, compressedsize}} ->
        chunk = bin_slice(data, fileoffset, compressedsize)

        if compressedsize == uncompressedsize do
          # just stored
          {:ok, chunk}
        else
          # compressed
          {:ok, LZ77.decode(chunk)}
        end
    end
  end

  defp read_cstr(data, offset) do
    case :binary.at(data, offset) do
      0 -> ""
      b -> <<b>> <> read_cstr(data, offset + 1)
    end
  end

  # Python bytes slicing clamps out-of-range offsets/lengths
  defp bin_slice(data, offset, len) do
    size = byte_size(data)
    offset = min(offset, size)
    binary_part(data, offset, min(len, size - offset))
  end

  ## musicdb.xml parsing

  defp parse_musicdb(xml) do
    {_root_tag, entries, _text} = parse_xml(xml)

    Map.new(entries, fn attr ->
      mcode = attr |> xfind!("mcode") |> xtext()

      entry =
        @mdb_attributes
        |> Enum.reduce(%{}, fn a, acc -> Map.put(acc, a, get_attr(attr, a)) end)
        |> Map.put("diffLv", attr |> xfind!("diffLv") |> xtext() |> String.split(" "))

      {mcode, entry}
    end)
  end

  # get_attr in the Python: missing element or missing text -> ""
  defp get_attr(attr, attrname) do
    case xfind(attr, attrname) do
      nil -> ""
      child -> child |> xtext() |> String.trim_trailing()
    end
  end

  # Minimal xmerl -> {tag, children, text} conversion (positional field
  # access, same as BaconNet.Kbinxml, but text is kept untrimmed because the
  # Python applies .rstrip() itself)
  defp parse_xml(bin) do
    {doc, _} =
      bin
      |> :binary.bin_to_list()
      |> :xmerl_scan.string(quiet: true, space: :preserve, encoding: :"utf-8")

    from_xmerl(doc)
  end

  defp from_xmerl(elem) do
    tag = elem |> Kernel.elem(1) |> to_string()
    content = Kernel.elem(elem, 8)
    children = for c <- content, is_tuple(c) and Kernel.elem(c, 0) == :xmlElement, do: from_xmerl(c)

    text =
      content
      |> Enum.filter(&(is_tuple(&1) and Kernel.elem(&1, 0) == :xmlText))
      |> Enum.map_join(fn t -> t |> Kernel.elem(4) |> List.to_string() end)

    {tag, children, text}
  end

  defp xfind({_tag, children, _text}, name) do
    Enum.find(children, fn {t, _children, _text} -> t == name end)
  end

  defp xfind!(node, name) do
    case xfind(node, name) do
      # Python dies with AttributeError on None.text
      nil -> raise "missing element #{inspect(name)}"
      child -> child
    end
  end

  defp xtext({_tag, _children, text}), do: text

  ## Misc helpers

  # int("".join(i for i in ddr_id if i.isnumeric()))
  defp numeric_id(s) do
    s
    |> :binary.bin_to_list()
    |> Enum.filter(&(&1 >= ?0 and &1 <= ?9))
    |> IO.iodata_to_binary()
    |> String.to_integer()
  end

  # DB docs in TinyDB insertion order (numeric id ascending)
  defp ordered_docs(table) do
    table
    |> table_with_ids()
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {_id, doc} -> doc end)
  end

  defp search_docs(table, conds) do
    table
    |> table_with_ids()
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.filter(fn {_id, doc} -> Enum.all?(conds, fn {k, v} -> Map.get(doc, k) == v end) end)
    |> Enum.map(fn {_id, doc} -> doc end)
  end

  defp table_with_ids(table) do
    DB
    |> :sys.get_state()
    |> Map.get(table, %{})
    |> Map.new(fn {id, doc} -> {String.to_integer(id), doc} end)
  end
end
