defmodule BaconNet.CardTest do
  use ExUnit.Case, async: true

  alias BaconNet.Card

  # Vectors from utils/card.py's self-test.
  test "to_konami_id/1 known vector" do
    assert Card.to_konami_id("0000000000000000") == "007TUT8XJNSSPN2P"
  end

  test "to_uid/1 known vector" do
    assert Card.to_uid("007TUT8XJNSSPN2P") == "0000000000000000"
  end

  test "roundtrip" do
    assert "000000100200F000" |> Card.to_konami_id() |> Card.to_uid() == "000000100200F000"
  end

  test "E004 card type roundtrip" do
    uid = "E004010203040506"
    assert uid |> Card.to_konami_id() |> Card.to_uid() == uid
  end

  test "invalid konami id raises" do
    assert_raise ArgumentError, fn -> Card.to_uid("007TUT8XJNSSPN2Q") end
  end
end
