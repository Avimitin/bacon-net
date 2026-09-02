defmodule BaconNet.LegacyApiTest do
  use ExUnit.Case, async: false

  import Plug.Test

  defp call(method, path) do
    conn(method, path)
    |> BaconNet.Router.call(BaconNet.Router.init([]))
  end

  test "legacy game APIs are disabled by default" do
    assert call(:get, "/iidx/profiles").status == 404
    assert call(:get, "/ddr/profiles").status == 404
    assert call(:get, "/gfdm/profiles").status == 404
    assert call(:patch, "/gfdm/profiles/123").status == 404
  end

  test "legacy game APIs dispatch when explicitly enabled" do
    Application.put_env(:bacon_net, :enable_legacy_game_apis, true)

    try do
      assert call(:get, "/iidx/profiles").status == 200
      assert call(:get, "/ddr/profiles").status == 200
      assert call(:get, "/gfdm/profiles").status == 200
    after
      Application.delete_env(:bacon_net, :enable_legacy_game_apis)
    end
  end
end
