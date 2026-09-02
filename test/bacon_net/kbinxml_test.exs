defmodule BaconNet.KbinxmlTest do
  use ExUnit.Case, async: true

  alias BaconNet.{E, Kbinxml, XNode}

  defp roundtrip(node, opts \\ []) do
    bin = Kbinxml.encode(node, opts)
    assert Kbinxml.is_binary_xml(bin)
    Kbinxml.decode(bin).node
  end

  test "encode produces valid header" do
    bin = Kbinxml.encode(E.e("response"))
    assert <<0xA0, 0x42, 0x80, 0x7F, _::binary>> = bin
  end

  test "void node roundtrip" do
    doc = roundtrip(E.e("response"))
    assert doc.tag == "response"
    assert doc.children == []
    assert doc.text == nil
  end

  test "attributes roundtrip sorted" do
    doc = roundtrip(E.e("card", refid: "E00401", dataid: "X"))
    assert XNode.attr(doc, "refid") == "E00401"
    assert XNode.attr(doc, "dataid") == "X"
    assert Enum.map(doc.attrs, &elem(&1, 0)) == ["dataid", "refid"]
  end

  test "typed scalars roundtrip" do
    node =
      E.e("root", [
        E.e("a", "-128", __type: "s8"),
        E.e("b", "255", __type: "u8"),
        E.e("c", "-32768", __type: "s16"),
        E.e("d", "65535", __type: "u16"),
        E.e("e", "-2147483648", __type: "s32"),
        E.e("f", "4294967295", __type: "u32"),
        E.e("g", "-9223372036854775808", __type: "s64"),
        E.e("h", "18446744073709551615", __type: "u64"),
        E.e("i", "1", __type: "bool"),
        E.e("j", "1700000000", __type: "time"),
        E.e("k", "127.0.0.1", __type: "ip4")
      ])

    doc = roundtrip(node)

    for {tag, text} <- [
          {"a", "-128"},
          {"b", "255"},
          {"c", "-32768"},
          {"d", "65535"},
          {"e", "-2147483648"},
          {"f", "4294967295"},
          {"g", "-9223372036854775808"},
          {"h", "18446744073709551615"},
          {"i", "1"},
          {"j", "1700000000"},
          {"k", "127.0.0.1"}
        ] do
      child = XNode.child(doc, tag)
      assert child.text == text, "#{tag}: #{inspect(child.text)}"
    end
  end

  test "float formatting matches reference" do
    doc = roundtrip(E.e("root", [E.e("f", "1.5", __type: "float")]))
    assert XNode.child(doc, "f").text == "1.500000"
  end

  test "arrays roundtrip with __count" do
    node = E.e("root", [E.e("arr", [1, 2, 3], __type: "u16")])
    doc = roundtrip(node)
    arr = XNode.child(doc, "arr")
    assert arr.text == "1 2 3"
    assert XNode.attr(arr, "__count") == "3"
  end

  test "vector types roundtrip" do
    doc = roundtrip(E.e("root", [E.e("v", "-1 2", __type: "2s16")]))
    v = XNode.child(doc, "v")
    assert v.text == "-1 2"
    assert XNode.attr(v, "__count") == nil
  end

  test "string roundtrip with cp932 text" do
    doc = roundtrip(E.e("root", [E.e("name", "テスト ＡＢＣ", __type: "str")]))
    assert XNode.child(doc, "name").text == "テスト ＡＢＣ"
  end

  test "binary roundtrip" do
    doc = roundtrip(E.e("root", [E.e("blob", "deadbeef", __type: "bin")]))
    blob = XNode.child(doc, "blob")
    assert blob.text == "deadbeef"
    assert XNode.attr(blob, "__size") == "4"
  end

  test "typeless text becomes str" do
    doc = roundtrip(E.e("root", [E.e("name", "hello")]))
    name = XNode.child(doc, "name")
    assert name.text == "hello"
    assert XNode.attr(name, "__type") == "str"
  end

  test "nested structure with attrs roundtrip" do
    node =
      E.e("response",
        E.e("services", [
          E.e("item", name: "cardmng", url: "http://localhost/core")
        ], expire: 10800, mode: "operation")
      )

    doc = roundtrip(node)
    services = XNode.child(doc, "services")
    assert XNode.attr(services, "expire") == "10800"
    item = XNode.child(services, "item")
    assert XNode.attr(item, "name") == "cardmng"
  end

  test "binary encode -> decode -> encode is stable" do
    node =
      E.e("response", [
        E.e("a", [1, 2, 3], __type: "u16"),
        E.e("b", "テスト", __type: "str"),
        E.e("c", "deadbeef", __type: "bin"),
        E.e("d", "1.5", __type: "float"),
        E.e("e", attr1: "x", attr2: "y")
      ])

    bin1 = Kbinxml.encode(node)
    bin2 = Kbinxml.encode(Kbinxml.decode(bin1).node)
    assert bin1 == bin2
  end

  test "decode text xml" do
    xml = ~s(<?xml version="1.0" encoding="UTF-8"?><response><card dataid="X" __type="str">abc</card></response>)
    doc = Kbinxml.decode(xml).node
    assert doc.tag == "response"
    card = XNode.child(doc, "card")
    assert XNode.attr(card, "dataid") == "X"
    assert card.text == "abc"
  end

  test "uncompressed encoding roundtrip" do
    node = E.e("response", [E.e("a", [1, 2], __type: "s32")])
    bin = Kbinxml.encode(node, compressed: false)
    assert <<0xA0, 0x45, _::binary>> = bin
    doc = Kbinxml.decode(bin).node
    assert XNode.child(doc, "a").text == "1 2"
  end

  test "utf8 encoding roundtrip" do
    node = E.e("response", [E.e("name", "テスト", __type: "str")])
    bin = Kbinxml.encode(node, encoding: :utf8)
    assert <<0xA0, 0x42, 0xA0, 0x5F, _::binary>> = bin
    doc = Kbinxml.decode(bin).node
    assert XNode.child(doc, "name").text == "テスト"
  end

  test "reference vectors decode and re-encode identically" do
    for fixture <- ["compressed", "uncompressed"] do
      path = Path.join([__DIR__, "fixtures", "test_#{fixture}.kbin"])

      if File.exists?(path) do
        bin = File.read!(path)
        doc = Kbinxml.decode(bin).node
        assert doc.tag == "response"
        re_encoded = Kbinxml.encode(doc, compressed: fixture == "compressed")
        assert re_encoded == bin, "re-encode mismatch for #{fixture}"
      end
    end
  end
end
