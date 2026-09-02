defmodule BaconNet.Modules.Gitadora.Playablemusic do
  @moduledoc "Port of modules/gitadora/playablemusic.py."

  alias BaconNet.{Core, E, Kbinxml, XNode}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"{ver}_playablemusic", "get", :gitadora_playablemusic_get}
      ]
    }
  end

  def gitadora_playablemusic_get(conn, ver) do
    {info, conn} = Core.process_request(conn)
    spec = info.spec

    is_delta =
      case spec do
        s when s in ["A", "B"] -> false
        s when s in ["C", "D"] -> true
      end

    # the game freezes if response has no songs
    # so make sure there is at least one
    # in case mdb isn't supplied
    songs = [
      {0,
       %{
         "xg_diff_list" => [
           "0",
           "100",
           "295",
           "395",
           "0",
           "0",
           "0",
           "0",
           "0",
           "0",
           "0",
           "160",
           "490",
           "585",
           "0"
         ],
         "contain_stat" => ["2", "2"],
         "data_ver" => 115
       }}
    ]

    short_ver =
      case ver do
        "galaxywave" -> "gw"
        "fuzzup" -> "fz"
        "highvoltage" -> "hv"
        "nextage" -> "nt"
        "exchain" -> "ex"
        "matixx" -> "mt"
        _ -> nil
      end

    short_ver = short_ver || "MISSING_FALLBACK"

    paths =
      if is_delta == true do
        [
          Path.join("modules/gitadora", "mdb_#{short_ver}_delta.xml"),
          "mdb_#{short_ver}_delta.xml"
        ]
      else
        [
          Path.join("modules/gitadora", "mdb_#{short_ver}.xml"),
          "mdb_#{short_ver}.xml"
        ]
      end

    songs =
      Enum.reduce_while(paths, songs, fn f, acc ->
        if File.exists?(f) do
          {:halt, load_mdb(acc, f, short_ver)}
        else
          {:cont, acc}
        end
      end)

    response =
      E.e("response",
        E.e("#{ver}_playablemusic", [
          E.e("hot", [
            E.e("major", -1, __type: "s32"),
            E.e("minor", -1, __type: "s32")
          ]),
          E.e(
            "musicinfo",
            Enum.map(songs, fn {s, song} ->
              cont_0 = String.to_integer(Enum.at(song["contain_stat"], 0))
              cont_1 = String.to_integer(Enum.at(song["contain_stat"], 1))

              E.e("music", [
                E.e("id", s, __type: "s32"),
                E.e("cont_gf", if(cont_0 != 0, do: 1, else: 0), __type: "bool"),
                E.e("cont_dm", if(cont_1 != 0, do: 1, else: 0), __type: "bool"),
                E.e("is_secret", 0, __type: "bool"),
                E.e("is_hot", if(rem(cont_0, 2) == 1 or rem(cont_1, 2) == 1, do: 1, else: 0),
                  __type: "bool"
                ),
                E.e("data_ver", song["data_ver"], __type: "s32"),
                E.e("seq_release_state", 1, __type: "s32"),
                E.e("diff", song["xg_diff_list"], __type: "u16")
              ])
            end),
            nr: length(songs)
          )
        ])
      )

    Core.send_response(conn, info, response)
  end

  defp load_mdb(songs, f, short_ver) do
    root = f |> File.read!() |> Kbinxml.decode() |> Map.get(:node)

    root.children
    |> Enum.filter(&(&1.tag == "mdb_data"))
    |> Enum.reduce(songs, fn entry, acc ->
      lvl = entry |> XNode.child("xg_diff_list") |> Map.get(:text) |> String.split(" ", trim: true)

      d_ver =
        if short_ver in ["fz", "hv", "nt", "ex"] do
          entry |> XNode.child("data_ver") |> Map.get(:text) |> String.to_integer()
        else
          115
        end

      mid = entry |> XNode.child("music_id") |> Map.get(:text)

      data = %{
        "xg_diff_list" => Enum.take(lvl, 5) ++ Enum.drop(lvl, 10) ++ Enum.slice(lvl, 5, 5),
        "contain_stat" =>
          entry |> XNode.child("contain_stat") |> Map.get(:text) |> String.split(" ", trim: true),
        "data_ver" => d_ver
      }

      put_song(acc, mid, data)
    end)
  end

  defp put_song(songs, mid, data) do
    case List.keyfind(songs, mid, 0) do
      nil -> songs ++ [{mid, data}]
      _ -> List.keyreplace(songs, mid, 0, {mid, data})
    end
  end
end
