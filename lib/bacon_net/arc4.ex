defmodule BaconNet.Arc4 do
  @moduledoc """
  RC4 cipher plus the e-amusement key derivation from utils/arc4.py:
  key = MD5(seconds <> prng <> internal_key).
  """

  import Bitwise

  @internal_key <<0x69, 0xD7, 0x46, 0x27, 0xD9, 0x85, 0xEE, 0x21, 0x87, 0x16, 0x15, 0x70,
                  0xD0, 0x8D, 0x93, 0xB1, 0x24, 0x55, 0x03, 0x5B, 0x6D, 0xF0, 0xD8, 0x20,
                  0x5D, 0xF5>>

  @doc "Derive the session key from the X-Eamuse-Info fields (raw bytes)."
  def eamuse_key(seconds, prng) do
    :crypto.hash(:md5, seconds <> prng <> @internal_key)
  end

  @doc "Encrypt or decrypt (RC4 is symmetric)."
  def crypt(key, data) do
    state = ksa(key)
    {out, _state} = prga(state, data, [])
    IO.iodata_to_binary(Enum.reverse(out))
  end

  # Key-scheduling algorithm: build the 256-byte permutation from the key.
  defp ksa(key) do
    key_bytes = :binary.bin_to_list(key)
    key_len = length(key_bytes)
    key_arr = key_bytes |> Enum.with_index() |> Map.new(fn {b, i} -> {i, b} end)

    {s, _j} =
      Enum.reduce(0..255, {Map.new(0..255, &{&1, &1}), 0}, fn i, {s, j} ->
        j = rem(j + Map.fetch!(s, i) + Map.fetch!(key_arr, rem(i, key_len)), 256)
        {swap(s, i, j), j}
      end)

    {s, 0, 0}
  end

  # Pseudo-random generation algorithm over the data.
  defp prga(state, <<>>, acc), do: {acc, state}

  defp prga({s, i, j}, <<byte, rest::binary>>, acc) do
    i = rem(i + 1, 256)
    j = rem(j + Map.fetch!(s, i), 256)
    s = swap(s, i, j)
    k = Map.fetch!(s, rem(Map.fetch!(s, i) + Map.fetch!(s, j), 256))
    prga({s, i, j}, rest, [bxor(byte, k) | acc])
  end

  defp swap(s, i, j) do
    si = Map.fetch!(s, i)
    sj = Map.fetch!(s, j)
    s |> Map.put(i, sj) |> Map.put(j, si)
  end
end
