defmodule BaconNet.LZ77 do
  @moduledoc """
  The e-amusement LZ77 variant, ported from utils/lz77.py.
  """

  import Bitwise

  @window_size 0x1000
  @window_mask @window_size - 1
  @threshold 3
  @inplace_threshold 0xA
  @look_range 0x200
  @max_len 0xF + @threshold

  ## Decode

  def decode(data) when is_binary(data) do
    do_decode(data, 0, :array.new(@window_size, default: 0), 0, [])
    |> IO.iodata_to_binary()
  end

  defp do_decode(data, pos, window, wcur, out) when pos < byte_size(data) do
    flag = :binary.at(data, pos)
    pos = pos + 1

    case decode_chunk(data, pos, flag, 0, window, wcur, out) do
      {:halt, _pos, _window, _wcur, out} ->
        Enum.reverse(out)

      {pos, window, wcur, out} ->
        do_decode(data, pos, window, wcur, out)
    end
  end

  defp do_decode(_data, _pos, _window, _wcur, out), do: Enum.reverse(out)

  defp decode_chunk(_data, pos, _flag, 8, window, wcur, out), do: {pos, window, wcur, out}

  defp decode_chunk(data, pos, flag, bit, window, wcur, out) do
    if pos >= byte_size(data) do
      {pos, window, wcur, out}
    else
      if (flag >>> bit &&& 1) == 1 do
        b = :binary.at(data, pos)
        window = :array.set(wcur, b, window)
        decode_chunk(data, pos + 1, flag, bit + 1, window, (wcur + 1) &&& @window_mask, [b | out])
      else
        w = :binary.at(data, pos) <<< 8 ||| :binary.at(data, pos + 1)

        if w == 0 do
          {:halt, pos + 2, window, wcur, out}
        else
          position = (wcur - (w >>> 4)) &&& @window_mask
          length = (w &&& 0x0F) + @threshold

          {window, wcur, out} =
            copy_match(window, wcur, position, length, out)

          decode_chunk(data, pos + 2, flag, bit + 1, window, wcur, out)
        end
      end
    end
  end

  defp copy_match(window, wcur, position, length, out) do
    Enum.reduce(1..length//1, {window, wcur, position, out}, fn _, {window, wcur, position, out} ->
      b = :array.get(position &&& @window_mask, window)
      window = :array.set(wcur, b, window)
      {window, (wcur + 1) &&& @window_mask, position + 1, [b | out]}
    end)
    |> then(fn {window, wcur, _position, out} -> {window, wcur, out} end)
  end

  ## Encode

  def encode(data) when is_binary(data) do
    window = :array.new(@window_size, default: 0)
    do_encode(data, 0, window, 0, [])
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  defp do_encode(data, pos, window, wcur, out) when pos < byte_size(data) do
    {group, pos, window, wcur, pad} = encode_group(data, pos, window, wcur, 0, [], 0)
    out = [group | out]

    out =
      if pos >= byte_size(data) do
        Enum.reduce(1..pad//1, out, fn _, acc -> [0 | acc] end)
      else
        out
      end

    if pos >= byte_size(data) do
      out
    else
      do_encode(data, pos, window, wcur, out)
    end
  end

  defp do_encode(_data, _pos, _window, _wcur, out), do: out

  # Encode one flag byte + up to 8 tokens. Returns {group_bytes, pos, window, wcur, pad}.
  # pad is 0 when input ran out mid-group (two zero bytes terminate the group),
  # 3 when the group completed exactly at end of input (reference behaviour).
  defp encode_group(data, pos, window, wcur, bit, tokens, flag) when bit < 8 do
    if pos >= byte_size(data) do
      # End of input inside a group: shift flags right, emit two zero bytes.
      flag = flag >>> (8 - bit)
      {[flag, Enum.reverse([0, 0 | tokens])], pos, window, wcur, 0}
    else
      case match_window(window, wcur, data, pos) do
        {mpos, length} when length >= @threshold ->
          byte1 = mpos >>> 4
          byte2 = ((mpos &&& 0x0F) <<< 4) ||| ((length - @threshold) &&& 0x0F)

          {window, wcur, pos} =
            Enum.reduce(1..length//1, {window, wcur, pos}, fn _, {window, wcur, pos} ->
              b = :binary.at(data, pos)
              {:array.set(wcur &&& @window_mask, b, window), wcur + 1, pos + 1}
            end)

          flag = (flag >>> 1) ||| 0
          encode_group(data, pos, window, wcur &&& @window_mask, bit + 1, [byte2, byte1 | tokens], flag)

        _ ->
          b = :binary.at(data, pos)
          window = :array.set(wcur, b, window)
          flag = (flag >>> 1) ||| 1 <<< 7

          encode_group(data, pos + 1, window, (wcur + 1) &&& @window_mask, bit + 1, [b | tokens], flag)
      end
    end
  end

  defp encode_group(_data, pos, window, wcur, 8, tokens, flag) do
    {[flag, Enum.reverse(tokens)], pos, window, wcur, 3}
  end

  defp match_window(window, wcur, data, dpos) do
    Enum.reduce_while(@threshold..(@look_range - 1)//1, nil, fn i, best ->
      length = match_current(window, (wcur - i) &&& @window_mask, i, data, dpos, 0)

      cond do
        length >= @inplace_threshold ->
          {:halt, {i, length}}

        length >= @threshold ->
          {:cont, {i, length}}

        true ->
          {:cont, best}
      end
    end)
  end

  defp match_current(window, pos, max_len, data, dpos, length) do
    if dpos + length < byte_size(data) and length < max_len and length < @max_len and
         :array.get((pos + length) &&& @window_mask, window) == :binary.at(data, dpos + length) do
      match_current(window, pos, max_len, data, dpos, length + 1)
    else
      length
    end
  end
end
