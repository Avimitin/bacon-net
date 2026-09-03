defmodule BaconNet.Kbinxml do
  @moduledoc """
  Konami binary XML (kbin) codec.

  The implementation follows the established kbinxml wire behavior described
  by kbinxml.py, bytebuffer.py, format_ids.py, and sixbit.py by mon.

  Decode: `decode/1` accepts binary kbin or text XML and returns an
  `%BaconNet.XNode{}` tree. Encode: `encode/2` turns a tree back into binary
  kbin (defaults: compressed node names, cp932 strings, like the reference).
  """

  import Bitwise

  alias BaconNet.{CP932, XNode}
  alias BaconNet.Kbinxml.{Formats, Sixbit}

  @signature 0xA0
  @sig_compressed 0x42
  @sig_uncompressed 0x45

  @encoding_bytes %{cp932: 0x80, ascii: 0x20, latin1: 0x40, euc_jp: 0x60, utf8: 0xA0}
  @byte_encodings %{
    0x00 => :cp932,
    0x20 => :ascii,
    0x40 => :latin1,
    0x60 => :euc_jp,
    0x80 => :cp932,
    0xA0 => :utf8
  }

  defstruct node: nil, encoding: :cp932, compressed: true

  ## Public API

  def is_binary_xml(<<@signature, sig, _::binary>>)
      when sig in [@sig_compressed, @sig_uncompressed],
      do: true

  def is_binary_xml(_), do: false

  @doc "Decode binary kbin or text XML into an XNode tree."
  def decode(input) when is_binary(input) do
    if is_binary_xml(input), do: from_binary(input), else: from_text(input)
  end

  @doc "Encode an XNode tree to binary kbin. Options: :encoding, :compressed."
  def encode(%XNode{} = node, opts \\ []) do
    encoding = Keyword.get(opts, :encoding, :cp932)
    compressed = Keyword.get(opts, :compressed, true)

    st = %{
      node: [],
      data: <<>>,
      byte: 0,
      word: 0,
      encoding: encoding,
      compressed: compressed
    }

    st = encode_node(st, node)
    st = put_node_u8(st, Formats.end_section_id() ||| 64)

    node_buf = st.node |> Enum.reverse() |> IO.iodata_to_binary() |> pad4()
    data = st.data
    enc_byte = Map.fetch!(@encoding_bytes, encoding)
    sig = if compressed, do: @sig_compressed, else: @sig_uncompressed

    header =
      <<@signature, sig, enc_byte, bxor(0xFF, enc_byte), byte_size(node_buf)::big-32>>

    header <> node_buf <> <<byte_size(data)::big-32>> <> data
  end

  @doc "Render an XNode tree as pretty-printed XML text (UTF-8)."
  def to_text(%XNode{} = node) do
    ~s(<?xml version='1.0' encoding='UTF-8'?>\n) <> render(node, 0)
  end

  ## Text XML parsing

  # xmerl record field positions (xmerl.hrl, stable across OTP versions):
  # xmlElement:   1=name, 7=attributes, 8=content
  # xmlAttribute: 1=name, 8=value
  # xmlText:      4=value
  # (positional access because Mix prunes the code path, so Record.extract
  # cannot locate xmerl.hrl at compile time)

  def from_text(text) when is_binary(text) do
    {doc, _} =
      text
      |> :binary.bin_to_list()
      |> :xmerl_scan.string(quiet: true, space: :preserve, encoding: :"utf-8")

    %__MODULE__{node: from_xmerl(doc), encoding: :utf8, compressed: true}
  end

  defp from_xmerl(elem) do
    tag = elem |> elem(1) |> to_string()

    attrs =
      elem
      |> elem(7)
      |> Enum.map(fn a -> {a |> elem(1) |> to_string(), a |> elem(8) |> List.to_string()} end)
      |> Enum.sort_by(&elem(&1, 0))

    content = elem(elem, 8)
    children = for c <- content, is_tuple(c) and elem(c, 0) == :xmlElement, do: from_xmerl(c)

    text =
      content
      |> Enum.filter(&(is_tuple(&1) and elem(&1, 0) == :xmlText))
      |> Enum.map_join(fn t -> t |> elem(4) |> List.to_string() end)
      |> String.trim()

    %XNode{tag: tag, attrs: attrs, children: children, text: if(text == "", do: nil, else: text)}
  end

  ## Binary decoding

  def from_binary(input) do
    <<@signature, sig, enc_byte, inv_enc, node_len::big-32, _::binary>> = input

    unless inv_enc == bxor(0xFF, enc_byte) do
      raise "invalid kbin encoding marker"
    end

    encoding = Map.fetch!(@byte_encodings, enc_byte)
    compressed = sig == @sig_compressed

    node_end = node_len + 8
    node_buf = binary_part(input, 8, node_len)

    st = %{
      input: input,
      main: node_end + 4,
      byte: node_end,
      word: node_end,
      encoding: encoding,
      compressed: compressed
    }

    case read_nodes(skip_zeros(node_buf), st, [%XNode{tag: "__root__"}]) do
      {%XNode{children: [doc]}, _st} ->
        %__MODULE__{node: doc, encoding: encoding, compressed: compressed}

      {%XNode{children: []}, _st} ->
        raise "empty kbin document"
    end
  end

  defp skip_zeros(<<0, rest::binary>>), do: skip_zeros(rest)
  defp skip_zeros(buf), do: buf

  defp read_nodes(<<>>, st, stack), do: finish(stack, st)

  defp read_nodes(buf, st, stack) do
    <<t, rest::binary>> = buf
    is_array = (t &&& 64) != 0
    t = t &&& 0xBF

    cond do
      t == Formats.attr_id() ->
        {name, rest} = read_name(rest, st)
        {value, st} = data_grab_string(st)
        [head | tail] = stack

        read_nodes(skip_zeros(rest), st, [%{head | attrs: head.attrs ++ [{name, value}]} | tail])

      t == Formats.node_end_id() ->
        stack = pop(stack)
        read_nodes(skip_zeros(rest), st, stack)

      t == Formats.end_section_id() ->
        finish(stack, st)

      t == Formats.void_id() ->
        {name, rest} = read_name(rest, st)
        node = %XNode{tag: fix_name(name)}
        read_nodes(skip_zeros(rest), st, [node | stack])

      fmt = Formats.format(t) ->
        {name, rest} = read_name(rest, st)
        {text, extra_attrs, st} = read_typed_value(st, fmt, is_array)

        node = %XNode{
          tag: fix_name(name),
          attrs: [{"__type", fmt.name} | extra_attrs],
          text: text
        }

        read_nodes(skip_zeros(rest), st, [node | stack])

      true ->
        raise "unknown kbin node type #{t}"
    end
  end

  defp finish([root], st), do: {%{root | children: Enum.reverse(root.children)}, st}

  defp finish(stack, st) do
    # Unterminated nodes: unwind like nodeEnd would.
    case pop(stack) do
      [_] = single -> finish(single, st)
      stack -> finish(stack, st)
    end
  end

  defp pop([node, parent | tail]) do
    node = %{
      node
      | children: Enum.reverse(node.children),
        attrs: Enum.sort_by(node.attrs, &elem(&1, 0))
    }

    [%{parent | children: [node | parent.children]} | tail]
  end

  # Stray nodeEnd with nothing to pop (matches reference: stay at root).
  defp pop(stack), do: stack

  defp read_name(rest, %{compressed: true}), do: Sixbit.unpack(rest)

  defp read_name(rest, %{compressed: false, encoding: encoding}) do
    <<len_byte, rest::binary>> = rest
    len = (len_byte &&& 0xBF) + 1
    <<name::binary-size(len), rest::binary>> = rest
    {decode_string(name, encoding), rest}
  end

  defp fix_name(<<>>), do: "_"

  defp fix_name(<<c, _::binary>> = name) do
    if (c >= ?a and c <= ?z) or (c >= ?A and c <= ?Z) or c == ?_ do
      name
    else
      "_" <> name
    end
  end

  defp read_typed_value(st, fmt, is_array) do
    {total_count, extra_attrs, aligned?, st} =
      cond do
        fmt.count == -1 ->
          {count, st} = data_get_u32(st)
          {count, [], false, st}

        is_array ->
          {byte_count, st} = data_get_u32(st)
          array_count = div(byte_count, fmt.size * fmt.count)
          {array_count * fmt.count, [{"__count", Integer.to_string(array_count)}], false, st}

        true ->
          {fmt.count, [], true, st}
      end

    {values, st} =
      if aligned? do
        data_grab_aligned(st, fmt, total_count)
      else
        {read_values(st.input, st.main, fmt, total_count),
         %{st | main: align4(st.main + fmt.size * total_count)}}
      end

    cond do
      fmt.name == "bin" ->
        hex =
          Enum.map_join(values, "", fn v ->
            v |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(2, "0")
          end)

        {hex, [{"__size", Integer.to_string(total_count)} | extra_attrs], st}

      fmt.name == "str" ->
        raw = values |> IO.iodata_to_binary()
        raw = binary_part(raw, 0, max(byte_size(raw) - 1, 0))
        {raw |> decode_string(st.encoding) |> String.trim(<<0>>), extra_attrs, st}

      true ->
        {Enum.map_join(values, " ", &format_value(fmt, &1)), extra_attrs, st}
    end
  end

  ## Data buffer read primitives (absolute offsets into the input binary)

  defp data_get_u32(st) do
    <<_::binary-size(st.main), v::big-32, _::binary>> = st.input
    {v, %{st | main: st.main + 4}}
  end

  defp data_grab_auto(st) do
    {size, st} = data_get_u32(st)
    bytes = binary_part(st.input, st.main, size)
    {bytes, %{st | main: align4(st.main + size)}}
  end

  defp data_grab_string(st) do
    {bytes, st} = data_grab_auto(st)
    bytes = binary_part(bytes, 0, max(byte_size(bytes) - 1, 0))
    {decode_string(bytes, st.encoding), st}
  end

  defp data_grab_aligned(st, fmt, count) do
    st = if rem(st.byte, 4) == 0, do: %{st | byte: st.main}, else: st
    st = if rem(st.word, 4) == 0, do: %{st | word: st.main}, else: st
    size = fmt.size * count

    {values, st} =
      cond do
        size == 1 ->
          {read_values(st.input, st.byte, fmt, count), %{st | byte: st.byte + size}}

        size == 2 ->
          {read_values(st.input, st.word, fmt, count), %{st | word: st.word + size}}

        true ->
          {read_values(st.input, st.main, fmt, count), %{st | main: align4(st.main + size)}}
      end

    trailing = max(st.byte, st.word)
    st = if st.main < trailing, do: %{st | main: align4(trailing)}, else: st
    {values, st}
  end

  defp align4(off), do: off + 3 &&& ~~~3

  ## Value unpacking

  defp read_values(_input, _offset, _fmt, 0), do: []

  defp read_values(input, offset, fmt, count) do
    for i <- 0..(count - 1)//1 do
      read_value_at(input, offset + i * fmt.size, fmt.type)
    end
  end

  defp read_value_at(input, offset, :b), do: read_int(input, offset, 8, true)
  defp read_value_at(input, offset, :B), do: read_int(input, offset, 8, false)
  defp read_value_at(input, offset, :h), do: read_int(input, offset, 16, true)
  defp read_value_at(input, offset, :H), do: read_int(input, offset, 16, false)
  defp read_value_at(input, offset, :i), do: read_int(input, offset, 32, true)
  defp read_value_at(input, offset, :I), do: read_int(input, offset, 32, false)
  defp read_value_at(input, offset, :q), do: read_int(input, offset, 64, true)
  defp read_value_at(input, offset, :Q), do: read_int(input, offset, 64, false)

  defp read_value_at(input, offset, :f) do
    <<_::binary-size(offset), v::big-float-32, _::binary>> = input
    v
  end

  defp read_value_at(input, offset, :d) do
    <<_::binary-size(offset), v::big-float-64, _::binary>> = input
    v
  end

  defp read_int(input, offset, bits, true) do
    <<_::binary-size(offset), v::big-signed-size(bits), _::binary>> = input
    v
  end

  defp read_int(input, offset, bits, false) do
    <<_::binary-size(offset), v::big-unsigned-size(bits), _::binary>> = input
    v
  end

  ## Encoding

  defp encode_node(st, %XNode{} = node) do
    type =
      case List.keyfind(node.attrs, "__type", 0) do
        {_, t} ->
          t

        nil ->
          if node.text != nil and String.trim(node.text) != "", do: "str", else: "void"
      end

    id = Formats.type_id(type)
    is_array = List.keymember?(node.attrs, "__count", 0)

    st = put_node_u8(st, id ||| if(is_array, do: 64, else: 0))
    st = put_node_name(st, node.tag)

    st =
      if type != "void" do
        encode_value(st, Formats.format(id), node, is_array)
      else
        st
      end

    st =
      node.attrs
      |> Enum.reject(fn {k, _} -> k in ["__type", "__size", "__count"] end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.reduce(st, fn {k, v}, st ->
        st = data_append_string(st, v)
        st |> put_node_u8(Formats.attr_id()) |> put_node_name(k)
      end)

    st = Enum.reduce(node.children, st, &encode_node(&2, &1))
    put_node_u8(st, Formats.node_end_id() ||| 64)
  end

  defp encode_value(st, fmt, node, is_array) do
    case fmt.name do
      "bin" ->
        data = Base.decode16!(String.upcase(node.text || ""))
        data_append_auto(st, data)

      "str" ->
        data = encode_string(node.text || "", st.encoding) <> <<0>>
        data_append_auto(st, data)

      _ ->
        values = parse_values(node.text || "", fmt)

        count_hint =
          case List.keyfind(node.attrs, "__count", 0) do
            {_, c} -> String.to_integer(c)
            nil -> nil
          end

        if count_hint && div(length(values), fmt.count) != count_hint do
          raise ArgumentError, "array length does not match __count attribute"
        end

        if is_array do
          data_append_auto(st, pack_values(fmt, values))
        else
          data_append_aligned(st, fmt, values)
        end
    end
  end

  defp data_append_auto(st, data) do
    %{st | data: pad4(st.data <> <<byte_size(data)::big-32>> <> data)}
  end

  defp data_append_string(st, s) do
    data_append_auto(st, encode_string(s, st.encoding) <> <<0>>)
  end

  defp data_append_aligned(st, fmt, values) do
    st = if rem(st.byte, 4) == 0, do: %{st | byte: byte_size(st.data)}, else: st
    st = if rem(st.word, 4) == 0, do: %{st | word: byte_size(st.data)}, else: st
    size = fmt.size * fmt.count
    packed = pack_values(fmt, values)

    cond do
      size == 1 ->
        st = if rem(st.byte, 4) == 0, do: %{st | data: st.data <> <<0::32>>}, else: st
        %{put_at(st, st.byte, packed) | byte: st.byte + size}

      size == 2 ->
        st = if rem(st.word, 4) == 0, do: %{st | data: st.data <> <<0::32>>}, else: st
        %{put_at(st, st.word, packed) | word: st.word + size}

      true ->
        %{st | data: pad4(st.data <> packed)}
    end
  end

  defp put_at(st, offset, bytes) do
    data = st.data
    tail_size = byte_size(data) - offset - byte_size(bytes)

    <<head::binary-size(offset), _::binary-size(byte_size(bytes)), tail::binary-size(tail_size)>> =
      data

    %{st | data: head <> bytes <> tail}
  end

  defp put_node_u8(st, b), do: %{st | node: [b | st.node]}

  defp put_node_name(st, name) do
    if st.compressed do
      %{st | node: [Sixbit.pack(name) | st.node]}
    else
      enc = encode_string(name, st.encoding)
      %{st | node: [[byte_size(enc) - 1 ||| 64, enc] | st.node]}
    end
  end

  ## Scalar helpers

  defp parse_values(text, fmt) do
    text
    |> String.split(" ", trim: true)
    |> Enum.map(&parse_value(fmt, &1))
  end

  defp parse_value(%{conv: :float}, s) do
    case Float.parse(s) do
      {v, _} -> v
      :error -> raise ArgumentError, "invalid float #{inspect(s)}"
    end
  end

  defp parse_value(%{conv: :ip4}, s) do
    [a, b, c, d] = s |> String.split(".") |> Enum.map(&String.to_integer/1)
    <<v::32>> = <<a, b, c, d>>
    v
  end

  defp parse_value(_, s), do: String.to_integer(String.trim(s))

  defp pack_values(fmt, values) do
    Enum.map_join(values, "", &pack_value(fmt, &1))
  end

  defp pack_value(%{type: :b}, v), do: <<v::big-signed-8>>
  defp pack_value(%{type: :B}, v), do: <<v::big-unsigned-8>>
  defp pack_value(%{type: :h}, v), do: <<v::big-signed-16>>
  defp pack_value(%{type: :H}, v), do: <<v::big-unsigned-16>>
  defp pack_value(%{type: :i}, v), do: <<v::big-signed-32>>
  defp pack_value(%{type: :I}, v), do: <<v::big-unsigned-32>>
  defp pack_value(%{type: :q}, v), do: <<v::big-signed-64>>
  defp pack_value(%{type: :Q}, v), do: <<v::big-unsigned-64>>
  defp pack_value(%{type: :f}, v), do: <<v::big-float-32>>
  defp pack_value(%{type: :d}, v), do: <<v::big-float-64>>

  defp format_value(%{conv: :float}, v), do: :io_lib.format("~.6f", [v]) |> IO.iodata_to_binary()

  defp format_value(%{conv: :ip4}, v) do
    <<a, b, c, d>> = <<v::big-32>>
    Enum.join([a, b, c, d], ".")
  end

  defp format_value(_, v), do: Integer.to_string(v)

  ## String encoding

  defp decode_string(bytes, :utf8), do: bytes
  defp decode_string(bytes, :ascii), do: bytes
  defp decode_string(bytes, :cp932), do: CP932.decode(bytes)
  defp decode_string(bytes, :latin1), do: :unicode.characters_to_binary(bytes, :latin1, :utf8)
  defp decode_string(_bytes, :euc_jp), do: raise("EUC-JP not supported")

  defp encode_string(str, :utf8), do: str

  defp encode_string(str, :ascii),
    do: for(<<c <- str>>, into: <<>>, do: if(c < 0x80, do: <<c>>, else: "?"))

  defp encode_string(str, :cp932), do: CP932.encode(str)

  defp encode_string(str, :latin1) do
    for <<cp::utf8 <- str>>, into: <<>>, do: if(cp <= 0xFF, do: <<cp>>, else: "?")
  end

  defp encode_string(_str, :euc_jp), do: raise("EUC-JP not supported")

  ## Misc

  defp pad4(bin) do
    case rem(byte_size(bin), 4) do
      0 -> bin
      n -> bin <> :binary.copy(<<0>>, 4 - n)
    end
  end

  ## Pretty printing

  defp render(%XNode{} = node, indent) do
    pad = String.duplicate("  ", indent)

    hint_attrs =
      ["__type", "__count", "__size"]
      |> Enum.flat_map(fn k ->
        case List.keyfind(node.attrs, k, 0) do
          {_, v} -> [~s( #{k}="#{v}")]
          nil -> []
        end
      end)
      |> Enum.join("")

    attrs =
      node.attrs
      |> Enum.reject(fn {k, _} -> k in ["__type", "__size", "__count"] end)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_join("", fn {k, v} -> ~s( #{k}="#{escape_attr(v)}") end)

    cond do
      node.children != [] ->
        children = Enum.map_join(node.children, "", &render(&1, indent + 1))

        "#{pad}<#{node.tag}#{hint_attrs}#{attrs}>\n#{children}#{pad}</#{node.tag}>\n"

      node.text not in [nil, ""] ->
        "#{pad}<#{node.tag}#{hint_attrs}#{attrs}>#{escape_text(node.text)}</#{node.tag}>\n"

      true ->
        "#{pad}<#{node.tag}#{hint_attrs}#{attrs}/>\n"
    end
  end

  defp escape_text(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
  end

  defp escape_attr(s) do
    s
    |> escape_text()
    |> String.replace("\"", "&quot;")
  end
end
