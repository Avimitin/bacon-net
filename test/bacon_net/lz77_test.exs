defmodule BaconNet.LZ77Test do
  use ExUnit.Case, async: true

  alias BaconNet.LZ77

  test "roundtrip empty" do
    assert LZ77.decode(LZ77.encode(<<>>)) == <<>>
  end

  test "roundtrip short literal" do
    assert LZ77.decode(LZ77.encode("hello")) == "hello"
  end

  test "roundtrip highly repetitive" do
    data = String.duplicate("abcabcabc", 500)
    assert LZ77.decode(LZ77.encode(data)) == data
  end

  test "roundtrip random data" do
    data = :crypto.strong_rand_bytes(4096)
    assert LZ77.decode(LZ77.encode(data)) == data
  end

  test "roundtrip mixed data larger than window" do
    data = String.duplicate("hello world ", 1000) <> :crypto.strong_rand_bytes(3000)
    assert LZ77.decode(LZ77.encode(data)) == data
  end

  test "repetitive data compresses" do
    data = String.duplicate("aaaaaaaaaa", 1000)
    assert byte_size(LZ77.encode(data)) < byte_size(data)
  end
end
