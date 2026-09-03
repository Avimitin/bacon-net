defmodule BaconNet.Kbinxml.Sixbit do
  @moduledoc """
  Six-bit packed node name codec for Konami binary XML.
  """

  import Bitwise

  @charmap "0123456789:ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"
  @bytemap @charmap
           |> :binary.bin_to_list()
           |> Enum.with_index()
           |> Map.new(fn {c, i} -> {c, i} end)

  @doc "Pack a node name. Returns iodata to append to the node buffer."
  def pack(name) when is_binary(name) do
    chars = for <<c <- name>>, do: Map.fetch!(@bytemap, c)
    n = length(chars)
    padding = rem(8 - rem(n * 6, 8), 8)

    bits = Enum.reduce(chars, 0, fn c, acc -> acc <<< 6 ||| c end)
    bits = bits <<< padding
    byte_len = div(n * 6 + padding, 8)
    [n, <<bits::big-size(byte_len)-unit(8)>>]
  end

  @doc "Unpack a node name from a buffer. Returns {name, rest}."
  def unpack(data) when is_binary(data) do
    <<length, rest::binary>> = data
    length_bits = length * 6
    length_bytes = div(length_bits + 7, 8)
    padding = rem(8 - rem(length_bits, 8), 8)

    <<raw::binary-size(length_bytes), rest::binary>> = rest
    bits = :binary.decode_unsigned(raw, :big) >>> padding

    chars =
      for _ <- 1..length//1, reduce: {bits, []} do
        {b, acc} -> {b >>> 6, [b &&& 0b111111 | acc]}
      end
      |> elem(1)

    name = Enum.map_join(chars, fn c -> <<:binary.at(@charmap, c)>> end)
    {name, rest}
  end
end
