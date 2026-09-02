defmodule BaconNet.Registry do
  @moduledoc """
  Registry of game protocol modules (the FastAPI routers of modules/).

  Each game module exposes `routes/0`:

      %{
        prefix: "/local",
        tag: "local",
        handlers: [
          {"IIDX33pc", "get", :iidx33pc_get},
          {"game", "sv{ver}_load", :game_sv_load}
        ]
      }

  Handler functions have the shape `fun.(conn)` or, for routes whose module
  or method contains `{ver}`, `fun.(conn, ver)`.
  """

  @modules [
    # core
    BaconNet.Modules.Core.Apsmanager,
    BaconNet.Modules.Core.Cardmng,
    BaconNet.Modules.Core.Dlstatus,
    BaconNet.Modules.Core.Eacoin,
    BaconNet.Modules.Core.Facility,
    BaconNet.Modules.Core.Ins,
    BaconNet.Modules.Core.Message,
    BaconNet.Modules.Core.Package,
    BaconNet.Modules.Core.Package2,
    BaconNet.Modules.Core.Pcbevent,
    BaconNet.Modules.Core.Pcbtracker,
    # iidx
    BaconNet.Modules.Iidx.Api,
    BaconNet.Modules.Iidx.Music,
    BaconNet.Modules.Iidx.Pc,
    BaconNet.Modules.Iidx.Ranking,
    BaconNet.Modules.Iidx.Shop,
    BaconNet.Modules.Iidx.Iidx29gamesystem,
    BaconNet.Modules.Iidx.Iidx29grade,
    BaconNet.Modules.Iidx.Iidx29lobby,
    BaconNet.Modules.Iidx.Iidx29music,
    BaconNet.Modules.Iidx.Iidx29pc,
    BaconNet.Modules.Iidx.Iidx29ranking,
    BaconNet.Modules.Iidx.Iidx29shop,
    BaconNet.Modules.Iidx.Iidx30gamesystem,
    BaconNet.Modules.Iidx.Iidx30grade,
    BaconNet.Modules.Iidx.Iidx30lobby,
    BaconNet.Modules.Iidx.Iidx30music,
    BaconNet.Modules.Iidx.Iidx30pc,
    BaconNet.Modules.Iidx.Iidx30ranking,
    BaconNet.Modules.Iidx.Iidx30shop,
    BaconNet.Modules.Iidx.Iidx31gamesystem,
    BaconNet.Modules.Iidx.Iidx31grade,
    BaconNet.Modules.Iidx.Iidx31lobby,
    BaconNet.Modules.Iidx.Iidx31music,
    BaconNet.Modules.Iidx.Iidx31pc,
    BaconNet.Modules.Iidx.Iidx31ranking,
    BaconNet.Modules.Iidx.Iidx31shop,
    BaconNet.Modules.Iidx.Iidx31streaming,
    BaconNet.Modules.Iidx.Iidx32gamesystem,
    BaconNet.Modules.Iidx.Iidx32grade,
    BaconNet.Modules.Iidx.Iidx32lobby,
    BaconNet.Modules.Iidx.Iidx32music,
    BaconNet.Modules.Iidx.Iidx32pc,
    BaconNet.Modules.Iidx.Iidx32ranking,
    BaconNet.Modules.Iidx.Iidx32shop,
    BaconNet.Modules.Iidx.Iidx32streaming,
    BaconNet.Modules.Iidx.Iidx33gamesystem,
    BaconNet.Modules.Iidx.Iidx33grade,
    BaconNet.Modules.Iidx.Iidx33lobby,
    BaconNet.Modules.Iidx.Iidx33music,
    BaconNet.Modules.Iidx.Iidx33pc,
    BaconNet.Modules.Iidx.Iidx33ranking,
    BaconNet.Modules.Iidx.Iidx33shop,
    BaconNet.Modules.Iidx.Iidx33streaming,
    # ddr
    BaconNet.Modules.Ddr.Api,
    BaconNet.Modules.Ddr.Eventlog,
    BaconNet.Modules.Ddr.Eventlog2,
    BaconNet.Modules.Ddr.Eventlog3,
    BaconNet.Modules.Ddr.Playdata3,
    BaconNet.Modules.Ddr.Playerdata,
    BaconNet.Modules.Ddr.Playerdata2,
    BaconNet.Modules.Ddr.System,
    BaconNet.Modules.Ddr.System2,
    BaconNet.Modules.Ddr.System3,
    BaconNet.Modules.Ddr.Tax,
    BaconNet.Modules.Ddr.Wordcheck3,
    # gitadora
    BaconNet.Modules.Gitadora.Api,
    BaconNet.Modules.Gitadora.Cardutil,
    BaconNet.Modules.Gitadora.Gameend,
    BaconNet.Modules.Gitadora.Gameinfo,
    BaconNet.Modules.Gitadora.Gametop,
    BaconNet.Modules.Gitadora.Lobby,
    BaconNet.Modules.Gitadora.Playablemusic,
    BaconNet.Modules.Gitadora.Shopinfo,
    # sdvx
    BaconNet.Modules.Sdvx.Eventlog,
    BaconNet.Modules.Sdvx.Game,
    # drs
    BaconNet.Modules.Drs.Eventlog,
    BaconNet.Modules.Drs.Game,
    # nostalgia
    BaconNet.Modules.Nostalgia.Op3Common,
    BaconNet.Modules.Nostalgia.Op3Player
  ]

  @routes (for module <- @modules,
               %{prefix: prefix, handlers: handlers} <- [module.routes()],
               {mod, method, fun} <- handlers do
             %{
               prefix: prefix,
               mod: mod,
               method: method,
               fun: fun,
               module: module,
               versioned: String.contains?(mod, "{ver}") or String.contains?(method, "{ver}")
             }
           end)

  @by_name Map.new(@routes, fn r -> {Atom.to_string(r.fun), r} end)

  @services @modules
            |> Enum.map(fn m ->
              info = m.routes()
              %{tag: info.tag, prefix: info.prefix}
            end)
            |> Enum.reject(fn %{tag: tag} ->
              String.starts_with?(tag, "api_") or tag == "slashless_forwarder"
            end)
            |> Enum.uniq_by(fn %{tag: tag} -> tag end)

  @doc "All registered routes."
  def routes, do: @routes

  @doc "Ordered, deduplicated service entries for services.get."
  def services, do: @services

  @api_routes (for module <- @modules,
                   info <- [module.routes()],
                   {http_method, segments, fun} <- Map.get(info, :api, []) do
                 %{
                   http_method: http_method,
                   prefix: info.prefix,
                   segments: segments,
                   fun: fun,
                   module: module
                 }
               end)

  @doc "Dispatch an API (JSON) request. Returns conn or nil when no route matches."
  def dispatch_api(conn, http_method, prefix, segments) do
    Enum.find_value(@api_routes, fn r ->
      if r.http_method == http_method and r.prefix == prefix and
           length(r.segments) == length(segments) do
        case match_segments(r.segments, segments, %{}) do
          nil -> nil
          params -> apply(r.module, r.fun, [conn, params])
        end
      end
    end)
  end

  defp match_segments([], [], params), do: params

  defp match_segments([p | ps], [s | ss], params) when is_atom(p) do
    match_segments(ps, ss, Map.put(params, Atom.to_string(p), s))
  end

  defp match_segments([p | ps], [s | ss], params) when is_binary(p) do
    if p == s, do: match_segments(ps, ss, params), else: nil
  end

  @doc "Dispatch a POST /:prefix/:gameinfo/:mod/:method request."
  def dispatch(conn, prefix, mod, method) do
    case find_route(prefix, mod, method) do
      nil ->
        nil

      %{versioned: true} = route ->
        ver = extract_ver(route, mod, method)
        apply(route.module, route.fun, [conn, ver])

      route ->
        apply(route.module, route.fun, [conn])
    end
  end

  @doc "Dispatch by handler function name (slashless forwarder)."
  def dispatch_by_name(conn, name, extra_arg \\ nil) do
    case Map.get(@by_name, name) do
      nil ->
        :not_found

      %{versioned: true} = route ->
        apply(route.module, route.fun, [conn, extra_arg])

      route ->
        apply(route.module, route.fun, [conn])
    end
  end

  def route_names, do: Map.keys(@by_name)

  defp find_route(prefix, mod, method) do
    Enum.find(@routes, fn r ->
      r.prefix == prefix and pattern_match?(r.mod, mod) and pattern_match?(r.method, method)
    end)
  end

  defp pattern_match?(pattern, value) do
    case String.split(pattern, "{ver}") do
      [^value] ->
        true

      [pre, post] ->
        String.starts_with?(value, pre) and String.ends_with?(value, post) and
          byte_size(value) >= byte_size(pre) + byte_size(post)

      _ ->
        false
    end
  end

  defp extract_ver(route, mod, method) do
    cond do
      String.contains?(route.method, "{ver}") ->
        extract(route.method, method)

      String.contains?(route.mod, "{ver}") ->
        extract(route.mod, mod)
    end
  end

  defp extract(pattern, value) do
    [pre, post] = String.split(pattern, "{ver}")

    value
    |> then(fn v -> if pre == "", do: v, else: String.trim_leading(v, pre) end)
    |> then(fn v -> if post == "", do: v, else: String.trim_trailing(v, post) end)
  end
end
