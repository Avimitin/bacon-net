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

  test "init starts empty when the database file is missing" do
    path = Path.join(System.tmp_dir!(), "bacon_db_missing_#{System.unique_integer([:positive])}.json")

    with_db_path(path, fn ->
      assert {:ok, %{}} = DB.init([])
    end)
  end

  test "init raises on malformed JSON" do
    path = Path.join(System.tmp_dir!(), "bacon_db_corrupt_#{System.unique_integer([:positive])}.json")
    File.write!(path, "{not json")

    with_db_path(path, fn ->
      assert_raise RuntimeError, ~r/malformed JSON/, fn -> DB.init([]) end
    end)

    File.rm(path)
  end

  test "init raises on unreadable database files other than :enoent" do
    dir = Path.join(System.tmp_dir!(), "bacon_db_dir_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    with_db_path(dir, fn ->
      assert_raise RuntimeError, ~r/failed to read database file/, fn -> DB.init([]) end
    end)

    File.rmdir(dir)
  end

  defp with_db_path(path, fun) do
    old = Application.get_env(:bacon_net, :db_path)
    Application.put_env(:bacon_net, :db_path, path)

    try do
      fun.()
    after
      if old,
        do: Application.put_env(:bacon_net, :db_path, old),
        else: Application.delete_env(:bacon_net, :db_path)
    end
  end
end
