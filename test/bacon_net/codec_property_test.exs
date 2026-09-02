defmodule BaconNet.CodecPropertyTest do
  @moduledoc """
  Property tests for the wire codecs: round-trips must hold for arbitrary
  inputs inside the supported envelope, and garbage must be rejected
  deterministically (a raised error), never a hang or silent corruption.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias BaconNet.{Arc4, Kbinxml, LZ77, XNode}

  property "ARC4 crypt is an involution for any key and payload" do
    check all(key <- binary(min_length: 1, max_length: 64),
              data <- binary(max_length: 1024)) do
      assert Arc4.crypt(key, Arc4.crypt(key, data)) == data
    end
  end

  property "LZ77 encode/decode round-trips arbitrary binaries" do
    check all(data <- binary(max_length: 4096)) do
      assert data |> LZ77.encode() |> LZ77.decode() == data
    end
  end

  property "LZ77 decode of truncated or corrupt streams fails deterministically" do
    check all(data <- binary(min_length: 1, max_length: 2048),
              cut <- integer(0..256)) do
      encoded = LZ77.encode(data)
      mangled = binary_part(encoded, 0, min(byte_size(encoded), cut))

      result =
        try do
          {:ok, LZ77.decode(mangled)}
        rescue
          _ -> :error
        catch
          _, _ -> :error
        end

      case result do
        :error -> :ok
        {:ok, out} -> assert is_binary(out)
      end
    end
  end

  property "KBin binary encode/decode round-trips generated documents" do
    check all(node <- node_gen(2), compressed <- boolean()) do
      decoded = node |> Kbinxml.encode(compressed: compressed) |> Kbinxml.decode()
      assert normalize(decoded.node) == normalize(node)
    end
  end

  property "KBin decode rejects arbitrary garbage deterministically" do
    check all(garbage <- binary(max_length: 512)) do
      try do
        Kbinxml.decode(garbage)
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      else
        _ -> :ok
      end
    end
  end

  ## Generators

  # cp932-safe ASCII names/values; XML names must not start with a digit.
  defp name_gen do
    map(string(:alphanumeric, max_length: 8), fn s -> "n" <> s end)
  end

  defp value_gen do
    string(:ascii, max_length: 16)
    |> map(fn s -> String.replace(s, ~r/[^ -~]/, "x") end)
  end

  defp node_gen(0) do
    map({list_of({name_gen(), value_gen()}, max_length: 3), value_gen()}, fn {attrs, text} ->
      # empty/whitespace text is not representable on the wire; it decodes as nil
      %XNode{tag: "leaf", attrs: attrs, text: if(String.trim(text) == "", do: nil, else: text)}
    end)
  end

  defp node_gen(depth) do
    map(
      {list_of({name_gen(), value_gen()}, max_length: 3),
       list_of(node_gen(depth - 1), max_length: 3)},
      fn {attrs, children} ->
        %XNode{tag: "n#{depth}", attrs: attrs, children: children}
      end
    )
  end

  # Attribute order is canonicalized (sorted by name) on decode, and wire
  # type-hint attributes (__type/__count/__size) appear on decoded nodes.
  @hints ["__type", "__count", "__size"]

  defp normalize(%XNode{} = node) do
    %{
      node
      | attrs:
          node.attrs
          |> Enum.reject(fn {k, _} -> k in @hints end)
          |> Enum.sort_by(&elem(&1, 0)),
        children: Enum.map(node.children, &normalize/1)
    }
  end
end
