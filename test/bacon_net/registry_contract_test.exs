defmodule BaconNet.RegistryContractTest do
  @moduledoc """
  Route inventory invariants: every registered route must have a callable
  handler, slashless handler names must be unique, and unknown routes must
  fail deterministically without writing anything.
  """

  use ExUnit.Case, async: false

  import Plug.Test

  alias BaconNet.{DB, E, Kbinxml, Registry, Shop}

  @model "LDJ:J:A:A:2025091700"
  @pcbid "CONTRACTPCBID001"

  describe "route inventory" do
    test "every protocol route has an exported handler with the right arity" do
      bad =
        Enum.reject(Registry.routes(), fn r ->
          String.starts_with?(r.prefix, "/") and
            function_exported?(r.module, r.fun, if(r.versioned, do: 2, else: 1))
        end)

      assert bad == []
    end

    test "every api route has an exported handler and a known http method" do
      api_routes =
        Registry.routes()
        |> Enum.map(& &1.module)
        |> Enum.uniq()
        |> Enum.flat_map(fn module ->
          for {http_method, segments, fun} <- module.routes() |> Map.get(:api, []) do
            {module, http_method, segments, fun}
          end
        end)

      assert Enum.all?(api_routes, fn {module, http_method, segments, fun} ->
               http_method in [:get, :post, :put, :patch, :delete] and is_list(segments) and
                 function_exported?(module, fun, 2)
             end)
    end

    test "slashless handler name collisions are always identical targets" do
      # DRS registers its two {player} variants under one handler; a name
      # may collide only when every colliding route is the same call.
      collisions =
        Registry.routes()
        |> Enum.group_by(& &1.fun)
        |> Enum.filter(fn {_, rs} -> length(rs) > 1 end)

      assert Enum.all?(collisions, fn {_fun, rs} ->
               rs |> Enum.map(&{&1.module, &1.fun, &1.versioned}) |> Enum.uniq() |> length() == 1
             end)
    end

    test "slashless DRS names resolve after stripping the player suffix" do
      for {method, base} <- [
            {"get_playdata", "drs_game_get_playdata"},
            {"lock_multi_login", "drs_game_lock_multi_login"},
            {"sign_up", "drs_game_sign_up"},
            {"get_musicscore", "drs_game_get_musicscore"}
          ],
          player <- ["1", "2"] do
        # the forwarder strips the trailing _1/_2 player variant
        name = "drs_game_#{method}_#{player}" |> String.replace(~r/_[12]$/, "")
        assert name == base
        assert base in Registry.route_names()
      end
    end

    test "service entries are unique per tag" do
      tags = Enum.map(Registry.services(), & &1.tag)
      assert tags == Enum.uniq(tags)
    end
  end

  describe "unknown routes" do
    setup do
      {:ok, _} = Shop.permit(@pcbid)
      on_exit(fn -> Shop.delete(@pcbid) end)
      :ok
    end

    defp post_raw(path, body) do
      conn(:post, path, body)
      |> Plug.Conn.put_req_header("content-length", to_string(byte_size(body)))
      |> BaconNet.Router.call(BaconNet.Router.init([]))
    end

    test "an unknown module/method returns 404 and writes nothing" do
      before = Map.new(DB.tables())

      body =
        Kbinxml.encode(E.e("call", E.e("nomodule", method: "nope"), model: @model, srcid: @pcbid))

      conn = post_raw("/local/#{@model}/nomodule/nope", body)

      assert conn.status == 404
      assert Map.new(DB.tables()) == before
    end

    test "services.get advertises the configured public URL, not the Host header" do
      body =
        Kbinxml.encode(E.e("call", E.e("services", method: "get"), model: @model, srcid: @pcbid))

      # Plug.Test defaults the Host header to www.example.com; it must never
      # leak into the advertised service URLs.
      conn = post_raw("/core/#{@model}/services/get", body)

      assert conn.status == 200
      refute conn.resp_body =~ "www.example.com"
      assert conn.resp_body =~ "127.0.0.1" or conn.resp_body =~ "http://"
    end
  end
end
