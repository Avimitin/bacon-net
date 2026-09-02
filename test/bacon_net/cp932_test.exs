defmodule BaconNet.CP932Test do
  use ExUnit.Case, async: true

  alias BaconNet.CP932

  test "ASCII passthrough" do
    assert CP932.encode("ABC123") == "ABC123"
    assert CP932.decode!("ABC123") == "ABC123"
  end

  test "full-width characters" do
    # Ａ = U+FF21 -> cp932 0x8260
    assert CP932.encode("Ａ") == <<0x82, 0x60>>
    assert CP932.decode!(<<0x82, 0x60>>) == "Ａ"
  end

  test "katakana" do
    # テ = 0x8365, ス = 0x8358, ト = 0x8367
    assert CP932.encode("テスト") == <<0x83, 0x65, 0x83, 0x58, 0x83, 0x67>>
    assert CP932.decode!(<<0x83, 0x65, 0x83, 0x58, 0x83, 0x67>>) == "テスト"
  end

  test "halfwidth katakana" do
    # ｱ = U+FF71 -> cp932 0xB1
    assert CP932.encode("ｱ") == <<0xB1>>
    assert CP932.decode!(<<0xB1>>) == "ｱ"
  end

  test "kanji roundtrip" do
    str = "音楽ゲーム"
    assert str |> CP932.encode() |> CP932.decode!() == str
  end

  test "unencodable becomes question mark" do
    assert CP932.encode("emoji 🎮") == "emoji ?"
  end

  test "roundtrip sample of common characters" do
    # Representative sample across the cp932 range (the reference codec has
    # duplicate mappings, so full-range roundtrip is not guaranteed there
    # either).
    samples =
      Enum.concat([
        ?A..?Z,
        ?a..?z,
        ?0..?9,
        [?ー, ?。, ?、, ?「, ?」],
        0x3041..0x3093,
        0x30A1..0x30F6,
        # common JIS X 0208 kanji (full ranges include chars absent from cp932)
        String.to_charlist("音楽日本語入力東京大阪京都名字山田鈴木"),
        0xFF01..0xFF5E
      ])

    for cp <- samples do
      str = <<cp::utf8>>
      assert str |> CP932.encode() |> CP932.decode!() == str
    end
  end
end
