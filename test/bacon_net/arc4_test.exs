defmodule BaconNet.Arc4Test do
  use ExUnit.Case, async: true

  alias BaconNet.Arc4

  # RFC 6229 style vectors.
  test "RC4 Key/Plaintext" do
    assert Arc4.crypt("Key", "Plaintext") == Base.decode16!("BBF316E8D940AF0AD3")
  end

  test "RC4 Wiki/pedia" do
    assert Arc4.crypt("Wiki", "pedia") == Base.decode16!("1021BF0420")
  end

  test "RC4 Secret/Attack at dawn" do
    assert Arc4.crypt("Secret", "Attack at dawn") == Base.decode16!("45A01F645FC35B383552544B9BF5")
  end

  test "symmetric roundtrip" do
    key = Arc4.eamuse_key(<<1, 2, 3, 4>>, <<5, 6>>)
    data = :crypto.strong_rand_bytes(512)
    assert Arc4.crypt(key, Arc4.crypt(key, data)) == data
  end

  test "eamuse key derivation is MD5(seconds <> prng <> internal)" do
    internal =
      <<0x69, 0xD7, 0x46, 0x27, 0xD9, 0x85, 0xEE, 0x21, 0x87, 0x16, 0x15, 0x70, 0xD0, 0x8D,
        0x93, 0xB1, 0x24, 0x55, 0x03, 0x5B, 0x6D, 0xF0, 0xD8, 0x20, 0x5D, 0xF5>>

    assert Arc4.eamuse_key(<<0xAA, 0xBB>>, <<0x01, 0x02>>) ==
             :crypto.hash(:md5, <<0xAA, 0xBB, 0x01, 0x02>> <> internal)
  end
end
