defmodule BaconNet.Kbinxml.Formats do
  @moduledoc """
  Node type table for Konami binary XML, ported from kbinxml's format_ids.py.

  Each entry: %{type: struct_type_char, size: byte_size, count: elems_per_value,
  name: canonical_name, conv: :int | :float | :ip4 | nil}
  """

  # struct char, byte size, count, names, conversion
  @raw [
    {1, nil, 0, 0, ~w(void), nil},
    {2, :b, 1, 1, ~w(s8), :int},
    {3, :B, 1, 1, ~w(u8), :int},
    {4, :h, 2, 1, ~w(s16), :int},
    {5, :H, 2, 1, ~w(u16), :int},
    {6, :i, 4, 1, ~w(s32), :int},
    {7, :I, 4, 1, ~w(u32), :int},
    {8, :q, 8, 1, ~w(s64), :int},
    {9, :Q, 8, 1, ~w(u64), :int},
    {10, :B, 1, -1, ~w(bin binary), nil},
    {11, :B, 1, -1, ~w(str string), nil},
    {12, :I, 4, 1, ~w(ip4), :ip4},
    {13, :I, 4, 1, ~w(time), :int},
    {14, :f, 4, 1, ~w(float f), :float},
    {15, :d, 8, 1, ~w(double d), :float},
    {16, :b, 1, 2, ~w(2s8), :int},
    {17, :B, 1, 2, ~w(2u8), :int},
    {18, :h, 2, 2, ~w(2s16), :int},
    {19, :H, 2, 2, ~w(2u16), :int},
    {20, :i, 4, 2, ~w(2s32), :int},
    {21, :I, 4, 2, ~w(2u32), :int},
    {22, :q, 8, 2, ~w(2s64 vs64), :int},
    {23, :Q, 8, 2, ~w(2u64 vu64), :int},
    {24, :f, 4, 2, ~w(2f), :float},
    {25, :d, 8, 2, ~w(2d vd), :float},
    {26, :b, 1, 3, ~w(3s8), :int},
    {27, :B, 1, 3, ~w(3u8), :int},
    {28, :h, 2, 3, ~w(3s16), :int},
    {29, :H, 2, 3, ~w(3u16), :int},
    {30, :i, 4, 3, ~w(3s32), :int},
    {31, :I, 4, 3, ~w(3u32), :int},
    {32, :q, 8, 3, ~w(3s64), :int},
    {33, :Q, 8, 3, ~w(3u64), :int},
    {34, :f, 4, 3, ~w(3f), :float},
    {35, :d, 8, 3, ~w(3d), :float},
    {36, :b, 1, 4, ~w(4s8), :int},
    {37, :B, 1, 4, ~w(4u8), :int},
    {38, :h, 2, 4, ~w(4s16), :int},
    {39, :H, 2, 4, ~w(4u16), :int},
    {40, :i, 4, 4, ~w(4s32 vs32), :int},
    {41, :I, 4, 4, ~w(4u32 vu32), :int},
    {42, :q, 8, 4, ~w(4s64), :int},
    {43, :Q, 8, 4, ~w(4u64), :int},
    {44, :f, 4, 4, ~w(4f vf), :float},
    {45, :d, 8, 4, ~w(4d), :float},
    {46, nil, 0, 0, ~w(attr), nil},
    {48, :b, 1, 16, ~w(vs8), :int},
    {49, :B, 1, 16, ~w(vu8), :int},
    {50, :h, 2, 8, ~w(vs16), :int},
    {51, :H, 2, 8, ~w(vu16), :int},
    {52, :b, 1, 1, ~w(bool b), :int},
    {53, :b, 1, 2, ~w(2b), :int},
    {54, :b, 1, 3, ~w(3b), :int},
    {55, :b, 1, 4, ~w(4b), :int},
    {56, :b, 1, 16, ~w(vb), :int}
  ]

  @formats Map.new(@raw, fn {id, type, size, count, names, conv} ->
             {id,
              %{
                id: id,
                type: type,
                size: size,
                count: count,
                name: hd(names),
                conv: conv
              }}
           end)

  @types (for {id, _type, _size, _count, names, _conv} <- @raw,
              name <- names do
            {name, id}
          end)
         |> Map.new()
         |> Map.merge(%{"nodeStart" => 1, "nodeEnd" => 190, "endSection" => 191})

  @doc "Format map keyed by node type id."
  def formats, do: @formats

  @doc "Node type name -> id map (includes nodeStart/nodeEnd/endSection)."
  def types, do: @types

  def type_id(name) when is_binary(name), do: Map.fetch!(@types, name)
  def format(id) when is_integer(id), do: Map.get(@formats, id)

  def node_end_id, do: 190
  def end_section_id, do: 191
  def attr_id, do: 46
  def void_id, do: 1
end
