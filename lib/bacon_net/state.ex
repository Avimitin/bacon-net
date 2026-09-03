defmodule BaconNet.State do
  @moduledoc """
  Tiny key-value Agent for ephemeral game and session state that does not
  require durable storage, such as eacoin sessions and lobby entries.
  """

  use Agent

  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def get(key, default \\ nil) do
    Agent.get(__MODULE__, &Map.get(&1, key, default))
  end

  def put(key, value) do
    Agent.update(__MODULE__, &Map.put(&1, key, value))
  end

  def update(key, default, fun) do
    Agent.get_and_update(__MODULE__, fn state ->
      value = Map.get(state, key, default)
      {ret, new_value} = fun.(value)
      {ret, Map.put(state, key, new_value)}
    end)
  end

  def delete(key) do
    Agent.update(__MODULE__, &Map.delete(&1, key))
  end
end
