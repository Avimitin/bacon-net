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

  test "insert_unless_exists inserts at most one matching document" do
    assert :inserted = DB.insert_unless_exists(@table, %{"a" => 1}, %{"a" => 1})
    assert :exists = DB.insert_unless_exists(@table, %{"a" => 1, "b" => 2}, %{"a" => 1})
    assert :inserted = DB.insert_unless_exists(@table, %{"a" => 2}, %{"a" => 2})

    assert DB.all(@table) == [%{"a" => 1}, %{"a" => 2}]
  end

  test "transaction rolls back every enclosed write on error" do
    DB.insert(@table, %{"a" => 1})

    assert {:error, :boom} =
             DB.transaction(fn ->
               DB.insert(@table, %{"a" => 2})
               DB.update(@table, %{"a" => 99}, %{"a" => 1})
               DB.rollback(:boom)
             end)

    assert DB.all(@table) == [%{"a" => 1}]
  end

  test "transaction commits all enclosed writes on success" do
    assert {:ok, :done} =
             DB.transaction(fn ->
               DB.insert(@table, %{"a" => 1})
               DB.insert(@table, %{"a" => 2})
               :done
             end)

    assert DB.all(@table) == [%{"a" => 1}, %{"a" => 2}]
  end

  test "concurrent inserts never share a doc id" do
    count = 50

    ids =
      1..count
      |> Task.async_stream(fn _ -> elem(DB.insert_with_id(@table, %{}), 0) end,
        max_concurrency: count,
        timeout: 30_000
      )
      |> Enum.map(fn {:ok, id} -> id end)

    assert Enum.uniq(ids) == ids
    assert length(ids) == count
  end

  test "conditions match nested maps and arrays by exact equality" do
    DB.insert(@table, %{"a" => %{"x" => 1, "y" => 2}})
    DB.insert(@table, %{"a" => %{"x" => 1}})
    DB.insert(@table, %{"a" => [1, 2]})
    DB.insert(@table, %{"a" => [1, 2, 3]})
    DB.insert(@table, %{"b" => 1})

    assert DB.search(@table, %{"a" => %{"x" => 1}}) == [%{"a" => %{"x" => 1}}]
    assert DB.search(@table, %{"a" => [1, 2]}) == [%{"a" => [1, 2]}]
    assert length(DB.search(@table, %{"a" => nil})) == 1
  end
end
