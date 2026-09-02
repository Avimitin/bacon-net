defmodule BaconNet.XNode do
  @moduledoc """
  XML element tree used across the server.

  Fields:
    * `:tag` — element name (binary)
    * `:attrs` — attribute list `[{name, value}]`, both binaries, sorted by name
    * `:children` — child `%XNode{}` list, in document order
    * `:text` — text content (binary) or nil
  """

  defstruct tag: nil, attrs: [], children: [], text: nil

  @type t :: %__MODULE__{
          tag: binary,
          attrs: [{binary, binary}],
          children: [t],
          text: binary | nil
        }

  @doc "Get an attribute value by name, or nil."
  def attr(%__MODULE__{attrs: attrs}, name) do
    case List.keyfind(attrs, name, 0) do
      {_, v} -> v
      nil -> nil
    end
  end

  @doc "Get an attribute parsed as integer, or nil/default."
  def attr_int(node, name, default \\ nil) do
    case attr(node, name) do
      nil -> default
      v -> String.to_integer(String.trim(v))
    end
  end

  @doc "First child with the given tag, or nil."
  def child(%__MODULE__{children: children}, tag) do
    Enum.find(children, &(&1.tag == tag))
  end

  @doc "All children with the given tag."
  def children(%__MODULE__{children: children}, tag) do
    Enum.filter(children, &(&1.tag == tag))
  end

  @doc "Text content parsed as a list of integers."
  def text_ints(%__MODULE__{text: nil}), do: []

  def text_ints(%__MODULE__{text: text}) do
    text |> String.split(" ", trim: true) |> Enum.map(&String.to_integer/1)
  end

  @doc "Sort attributes by name (canonical form used by the kbin encoder)."
  def sort_attrs(%__MODULE__{attrs: attrs} = node) do
    %{node | attrs: Enum.sort_by(attrs, &elem(&1, 0))}
  end
end
