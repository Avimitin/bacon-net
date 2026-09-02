defmodule BaconNet.Modules.Core.Cardmng do
  @moduledoc "Port of modules/core/cardmng.py."

  alias BaconNet.{Core, DB, E, XNode}

  def routes do
    %{
      prefix: "/core",
      tag: "cardmng",
      handlers: [
        {"cardmng", "authpass", :cardmng_authpass},
        {"cardmng", "bindmodel", :cardmng_bindmodel},
        {"cardmng", "getrefid", :cardmng_getrefid},
        {"cardmng", "inquire", :cardmng_inquire}
      ]
    }
  end

  @target_table %{
    "LDJ" => "iidx_profile",
    "MDX" => "ddr_profile",
    "KFC" => "sdvx_profile",
    "M32" => "gitadora_profile",
    "PAN" => "nostalgia_profile",
    "REC" => "dancerush_profile",
    "JDZ" => "iidx_profile",
    "KDZ" => "iidx_profile"
  }

  def get_target_table(game_id), do: Map.fetch!(@target_table, game_id)

  def get_profile(game_id, cid) do
    DB.get(get_target_table(game_id), %{"card" => cid}) || %{"card" => cid, "version" => %{}}
  end

  def get_game_profile(game_id, game_version, cid) do
    profile = get_profile(game_id, cid)
    get_in(profile, ["version", to_string(game_version)]) || %{}
  end

  def create_profile(game_id, game_version, cid, pin) do
    _ = game_version
    profile = get_profile(game_id, cid) |> Map.put("pin", pin)
    DB.upsert(get_target_table(game_id), profile, %{"card" => cid})
  end

  def cardmng_authpass(conn) do
    {info, conn} = Core.process_request(conn)
    node = Core.module_node(info)

    cid = XNode.attr(node, "refid")
    passwd = XNode.attr(node, "pass")

    profile = get_profile(info.model, cid)
    status = if passwd == Map.get(profile, "pin"), do: 0, else: 116

    Core.send_response(conn, info, E.e("response", E.e("authpass", status: status)))
  end

  def cardmng_bindmodel(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("bindmodel", dataid: 1)))
  end

  def cardmng_getrefid(conn) do
    {info, conn} = Core.process_request(conn)
    node = Core.module_node(info)

    cid = XNode.attr(node, "cardid")
    passwd = XNode.attr(node, "passwd")

    create_profile(info.model, info.game_version, cid, passwd)

    Core.send_response(conn, info, E.e("response", E.e("getrefid", dataid: cid, refid: cid)))
  end

  def cardmng_inquire(conn) do
    {info, conn} = Core.process_request(conn)
    node = Core.module_node(info)

    cid = XNode.attr(node, "cardid")

    profile = get_game_profile(info.model, info.game_version, cid)

    {binded, newflag, status} =
      if profile == %{}, do: {0, 1, 112}, else: {1, 0, 0}

    Core.send_response(
      conn,
      info,
      E.e(
        "response",
        E.e("inquire",
          dataid: cid,
          ecflag: 1,
          expired: 0,
          binded: binded,
          newflag: newflag,
          refid: cid,
          status: status
        )
      )
    )
  end
end
