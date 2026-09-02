defmodule BaconNet.DBTest do
  use ExUnit.Case, async: false

  alias BaconNet.DB

  @table "test_widget"

  setup do
    DB.drop_table(@table)
    on_exit(fn -> DB.drop_table(@table) end)
    :ok
  end

  test "insert_with_id assigns ascending ids" do
    assert {"1", %{"a" => 1}} = DB.insert_with_id(@table, %{"a" => 1})
    assert {"2", %{"a" => 2}} = DB.insert_with_id(@table, %{"a" => 2})
  end

  test "get_by_id / all_with_ids" do
    {id, _} = DB.insert_with_id(@table, %{"a" => 1})
    DB.insert_with_id(@table, %{"a" => 2})

    assert DB.get_by_id(@table, id) == %{"a" => 1}
    assert DB.get_by_id(@table, "999") == nil
    assert DB.all_with_ids(@table) == [{"1", %{"a" => 1}}, {"2", %{"a" => 2}}]
  end

  test "replace_by_id swaps the whole document" do
    {id, _} = DB.insert_with_id(@table, %{"a" => 1, "b" => 2})

    assert DB.replace_by_id(@table, id, %{"c" => 3}) == :ok
    assert DB.get_by_id(@table, id) == %{"c" => 3}
    assert DB.replace_by_id(@table, "999", %{}) == :not_found
  end

  test "update_by_id merges fields" do
    {id, _} = DB.insert_with_id(@table, %{"a" => 1, "b" => 2})

    assert DB.update_by_id(@table, id, %{"b" => 5, "c" => 6}) == :ok
    assert DB.get_by_id(@table, id) == %{"a" => 1, "b" => 5, "c" => 6}
    assert DB.update_by_id(@table, "999", %{"b" => 0}) == :not_found
  end

  test "remove_by_id" do
    {id, _} = DB.insert_with_id(@table, %{"a" => 1})

    assert DB.remove_by_id(@table, id) == :ok
    assert DB.get_by_id(@table, id) == nil
    assert DB.remove_by_id(@table, id) == :not_found
  end

  test "tables lists names with counts sorted" do
    DB.drop_table(@table)
    DB.insert_with_id(@table, %{"a" => 1})

    assert Enum.find(DB.tables(), fn {name, _} -> name == @table end) == {@table, 1}
    assert DB.tables() == Enum.sort(DB.tables())
  end
end
