defmodule BaconNet.CP932 do
  @moduledoc """
  Minimal cp932 (Windows Shift-JIS) codec backed by a mapping table generated
  into the build output by scripts/gen_cp932.py.

  Tables are loaded into `:persistent_term` on first use.
  """

  import Bitwise

  @external_resource Path.expand("../../scripts/gen_cp932.py", __DIR__)

  @doc "Decode a cp932 binary to a UTF-8 string. Raises on invalid input."
  def decode!(bin) when is_binary(bin) do
    {dec, _} = tables()
    do_decode(bin, dec, [])
  end

  @doc "Lenient decode: falls back to UTF-8 (with replacement) on error."
  def decode(bin) when is_binary(bin) do
    decode!(bin)
  rescue
    _ ->
      case String.valid?(bin) do
        true -> bin
        false -> replace_invalid(bin)
      end
  end

  defp replace_invalid(bin) do
    for <<b <- bin>>, into: <<>> do
      if b < 0x80, do: <<b>>, else: "?"
    end
  end

  @doc """
  Encode a UTF-8 string to cp932. Unencodable codepoints become "?",
  mirroring Python's `encode("cp932", "replace")`.
  """
  def encode(str) when is_binary(str) do
    {_, enc} = tables()

    for <<cp::utf8 <- str>>, into: <<>> do
      case enc do
        %{^cp => v} when v < 0x100 -> <<v>>
        %{^cp => v} -> <<v::16>>
        _ -> "?"
      end
    end
  end

  defp do_decode(<<>>, _dec, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp do_decode(<<b, rest::binary>>, dec, acc) when b < 0x80 do
    do_decode(rest, dec, [<<b>> | acc])
  end

  defp do_decode(<<b, rest::binary>>, dec, acc) do
    case dec do
      %{^b => s} ->
        do_decode(rest, dec, [s | acc])

      _ ->
        case rest do
          <<b2, rest2::binary>> ->
            v = b <<< 8 ||| b2

            case dec do
              %{^v => s} -> do_decode(rest2, dec, [s | acc])
              _ -> raise "invalid cp932 sequence #{inspect(<<b, b2>>)}"
            end

          _ ->
            raise "truncated cp932 sequence #{inspect(<<b>>)}"
        end
    end
  end

  defp tables do
    case :persistent_term.get({__MODULE__, :tables}, nil) do
      nil ->
        tables = load_table()
        :persistent_term.put({__MODULE__, :tables}, tables)
        tables

      tables ->
        tables
    end
  end

  defp table_path do
    case :code.priv_dir(:bacon_net) do
      {:error, _} -> Path.expand("../../priv/cp932.bin", __DIR__)
      dir -> Path.join(to_string(dir), "cp932.bin")
    end
  end

  defp load_table do
    <<"CP93", dec_count::32, rest::binary>> = File.read!(table_path())
    {dec, rest} = read_dec(rest, dec_count, %{})
    <<enc_count::32, rest::binary>> = rest
    {enc, _} = read_enc(rest, enc_count, %{})
    {dec, enc}
  end

  defp read_dec(rest, 0, acc), do: {acc, rest}

  defp read_dec(<<v::16, len::8, s::binary-size(len), rest::binary>>, n, acc) do
    read_dec(rest, n - 1, Map.put(acc, v, s))
  end

  defp read_enc(rest, 0, acc), do: {acc, rest}

  defp read_enc(<<cp::32, v::16, rest::binary>>, n, acc) do
    read_enc(rest, n - 1, Map.put(acc, cp, v))
  end
end
