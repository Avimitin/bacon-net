defmodule BaconNet.E do
  @moduledoc """
  Builder for e-amusement protocol element trees.

  All elements are created through `e/1..3`:

      E.e("response", [E.e("services", expire: 10800, mode: "operation")])
      E.e("result", 0, __type: "u8")
      E.e("flg1", [-1, -1], __type: "s64")
      E.e("pcdata", dach: 1, name: "ＤＪ")

  The reserved option keys `:__type`, `:__count` and `:__size` map to the
  kbinxml type-hint attributes; every other option becomes a plain attribute.

  Value conversion follows the protocol's wire conventions:
    * integers/floats/binaries — stringified
    * booleans — `"1"` / `"0"`
    * lists — space-joined, `__count` set to the length (for node values),
      plain space-joined string (for attribute values)
  """

  alias BaconNet.XNode

  @reserved [:__type, :__count, :__size]

  def e(tag) when is_binary(tag), do: %XNode{tag: tag}

  def e(tag, arg) when is_binary(tag), do: build(tag, arg, [])

  def e(tag, arg, opts) when is_binary(tag) and is_list(opts) do
    {attrs, hints} = split_opts(opts)
    node = build(tag, arg, hints)
    %{node | attrs: attrs ++ node.attrs}
  end

  defp build(tag, arg, hints)

  # attrs-only form: E.e("item", name: "x", url: "y")
  defp build(tag, opts, []) when is_list(opts) do
    if keyword?(opts) do
      {attrs, hints} = split_opts(opts)
      %XNode{tag: tag, attrs: attrs, text: nil} |> apply_hints(hints)
    else
      build_value(tag, opts, [])
    end
  end

  defp build(tag, arg, hints) do
    build_value(tag, arg, hints)
  end

  defp build_value(tag, arg, hints) do
    node =
      case arg do
        nil ->
          %XNode{tag: tag}

        %XNode{} = child ->
          %XNode{tag: tag, children: [child]}

        list when is_list(list) ->
          if list != [] and Enum.all?(list, &match?(%XNode{}, &1)) do
            %XNode{tag: tag, children: list}
          else
            text = Enum.map_join(list, " ", &stringify/1)
            hints = Keyword.put_new(hints, :__count, length(list))
            %XNode{tag: tag, text: text} |> apply_hints(hints)
          end

        scalar ->
          %XNode{tag: tag, text: stringify(scalar)}
      end

    apply_hints(node, hints)
  end

  defp apply_hints(node, hints) do
    hints = for {k, v} <- hints, k in @reserved, do: {Atom.to_string(k), to_string(v)}
    attrs = Enum.uniq_by(hints ++ node.attrs, &elem(&1, 0))
    %{node | attrs: attrs}
  end

  defp split_opts(opts) do
    Enum.reduce(opts, {[], []}, fn
      {k, v}, {attrs, hints} when k in @reserved ->
        {attrs, hints ++ [{k, v}]}

      {k, v}, {attrs, hints} ->
        name = if is_atom(k), do: Atom.to_string(k), else: to_string(k)
        {attrs ++ [{name, stringify(v)}], hints}
    end)
  end

  defp keyword?(list), do: Enum.all?(list, &match?({k, _} when is_atom(k), &1))

  @doc "Stringify a scalar for protocol attributes and values."
  def stringify(v) when is_binary(v), do: v
  def stringify(v) when is_integer(v), do: Integer.to_string(v)
  def stringify(v) when is_float(v), do: to_string(v)
  def stringify(true), do: "1"
  def stringify(false), do: "0"
  def stringify(nil), do: ""

  def stringify(v) when is_list(v) do
    Enum.map_join(v, " ", &stringify/1)
  end

  def stringify(v) when is_atom(v), do: Atom.to_string(v)
end
