defmodule BaconNet.Card do
  @moduledoc """
  e-amusement card ID <-> Konami ID conversion.
  https://bsnk.me/eamuse/
  """

  import Bitwise

  @key for(i <- ~c"?I'llB2c.YouXXXeMeHaYpy!", do: i * 2) |> :binary.list_to_bin()
  @iv <<0::64>>

  @valid_characters "0123456789ABCDEFGHJKLMNPRSTUWXYZ"

  def valid_characters, do: @valid_characters

  defp enc_des(uid), do: :crypto.crypto_one_time(:des_ede3_cbc, @key, @iv, uid, true)
  defp dec_des(uid), do: :crypto.crypto_one_time(:des_ede3_cbc, @key, @iv, uid, false)

  defp checksum(data) when is_list(data) do
    chk =
      data
      |> Enum.take(15)
      |> Enum.with_index()
      |> Enum.reduce(0, fn {b, i}, acc -> acc + b * (rem(i, 3) + 1) end)

    fold_checksum(chk)
  end

  defp fold_checksum(chk) when chk > 31, do: fold_checksum((chk >>> 5) + (chk &&& 31))
  defp fold_checksum(chk), do: chk

  defp pack_5(data) do
    bit_count = length(data) * 5
    pad = rem(8 - rem(bit_count, 8), 8)
    bits = for b <- data, into: <<>>, do: <<b::5>>
    <<bits::bitstring, 0::size(pad)>>
  end

  defp unpack_5(data) do
    bit_count = byte_size(data) * 8
    pad = rem(5 - rem(bit_count, 5), 5)
    data = <<data::bitstring, 0::size(pad)>>
    total = div(bit_count + pad, 5)

    for i <- 0..(total - 1)//1 do
      skip = i * 5
      <<_::size(skip)-unit(1), v::5, _::bitstring>> = data
      v
    end
  end

  @doc "Convert a 16-hex-char card UID to a 16-char Konami ID."
  def to_konami_id(uid) when byte_size(uid) == 16 do
    up = String.upcase(uid)

    card_type =
      cond do
        String.starts_with?(up, "E004") -> 1
        String.starts_with?(up, "0") -> 2
        true -> raise ArgumentError, "invalid UID prefix"
      end

    kid = Base.decode16!(up)

    out =
      kid
      |> :binary.bin_to_list()
      |> Enum.reverse()
      |> IO.iodata_to_binary()
      |> enc_des()
      |> unpack_5()
      |> Enum.take(13)

    out = out ++ [0, 0, 0]
    out = List.replace_at(out, 0, bxor(Enum.at(out, 0), card_type))
    out = List.replace_at(out, 13, 1)

    out =
      Enum.reduce(1..13, out, fn i, acc ->
        List.replace_at(acc, i, bxor(Enum.at(acc, i), Enum.at(acc, i - 1)))
      end)

    out = List.replace_at(out, 14, card_type)
    out = List.replace_at(out, 15, checksum(out))

    Enum.map_join(out, fn c -> <<:binary.at(@valid_characters, c)>> end)
  end

  @doc "Convert a 16-char Konami ID back to the 16-hex-char card UID."
  def to_uid(konami_id) when byte_size(konami_id) == 16 do
    card_type =
      case String.at(konami_id, 14) do
        "1" -> 1
        "2" -> 2
        _ -> raise ArgumentError, "invalid ID"
      end

    card =
      for <<c <- konami_id>> do
        idx = :binary.match(@valid_characters, <<c>>)
        if idx == :nomatch, do: raise(ArgumentError, "ID contains invalid characters")
        elem(idx, 0)
      end

    unless rem(Enum.at(card, 11), 2) == rem(Enum.at(card, 12), 2),
      do: raise(ArgumentError, "parity check failed")

    unless Enum.at(card, 13) == bxor(Enum.at(card, 12), 1),
      do: raise(ArgumentError, "card invalid")

    unless Enum.at(card, 15) == checksum(card),
      do: raise(ArgumentError, "checksum failed")

    card =
      Enum.reduce(13..1//-1, card, fn i, acc ->
        List.replace_at(acc, i, bxor(Enum.at(acc, i), Enum.at(acc, i - 1)))
      end)

    card = List.replace_at(card, 0, bxor(Enum.at(card, 0), card_type))

    card_id =
      card
      |> Enum.take(13)
      |> pack_5()
      |> binary_part(0, 8)
      |> dec_des()
      |> :binary.bin_to_list()
      |> Enum.reverse()
      |> IO.iodata_to_binary()
      |> Base.encode16()

    case card_type do
      1 ->
        unless String.starts_with?(card_id, "E004"), do: raise(ArgumentError, "invalid card type")

      2 ->
        unless String.starts_with?(card_id, "0"), do: raise(ArgumentError, "invalid card type")
    end

    card_id
  end

  @doc """
  Normalize user-provided card input (card UID or Konami ID, tolerant of
  common lookalike characters) to `%{"uid" => _, "konami_id" => _}`.
  Returns nil when the input cannot be parsed.
  """
  def normalize(input) when is_binary(input) do
    card =
      input
      |> String.upcase()
      |> String.replace("I", "1")
      |> String.replace("O", "0")
      |> String.replace("Q", "0")
      |> String.replace("V", "U")

    if String.starts_with?(card, "E004") or String.starts_with?(card, "012E") do
      uid =
        card
        |> :binary.bin_to_list()
        |> Enum.filter(&(&1 in ~c"0123456789ABCDEF"))
        |> IO.iodata_to_binary()

      case to_konami_id_safe(uid) do
        {:ok, kid} -> %{"uid" => uid, "konami_id" => kid}
        :error -> nil
      end
    else
      valid = @valid_characters |> :binary.bin_to_list()
      kid = card |> :binary.bin_to_list() |> Enum.filter(&(&1 in valid)) |> IO.iodata_to_binary()

      case to_uid_safe(kid) do
        {:ok, uid} -> %{"uid" => uid, "konami_id" => kid}
        :error -> nil
      end
    end
  end

  def normalize(_), do: nil

  defp to_konami_id_safe(uid) do
    {:ok, to_konami_id(uid)}
  rescue
    _ -> :error
  end

  defp to_uid_safe(kid) do
    {:ok, to_uid(kid)}
  rescue
    _ -> :error
  end
end
