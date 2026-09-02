defmodule BaconNet.Modules.Iidx.Iidx32lobby do
  @moduledoc "Port of modules/iidx/iidx32lobby.py."

  alias BaconNet.{Core, E, State, XNode}

  @arena_host_key :iidx32lobby_arena_host
  @bpl_host_key :iidx32lobby_bpl_host

  def routes do
    %{
      prefix: "/lobby2",
      tag: "lobby2",
      handlers: [
        {"IIDX32lobby", "entry", :iidx32lobby_entry},
        {"IIDX32lobby", "update", :iidx32lobby_update},
        {"IIDX32lobby", "delete", :iidx32lobby_delete},
        {"IIDX32lobby", "bplbattle_entry", :iidx32lobby_bplbattle_entry},
        {"IIDX32lobby", "bplbattle_update", :iidx32lobby_bplbattle_update},
        {"IIDX32lobby", "bplbattle_delete", :iidx32lobby_bplbattle_delete}
      ]
    }
  end

  def iidx32lobby_entry(conn) do
    {info, conn} = Core.process_request(conn)
    node = Core.module_node(info)

    _sp_dp = node |> XNode.child("play_style") |> text()
    arena_class = node |> XNode.child("arena_class") |> text()
    address = XNode.child(node, "address")
    ga = address |> XNode.child("ga") |> text() |> String.split(~r/\s+/, trim: true)
    gp = address |> XNode.child("gp") |> text()
    la = address |> XNode.child("la") |> text() |> String.split(~r/\s+/, trim: true)

    now = :os.system_time(:second)

    response =
      State.update(@arena_host_key, %{}, fn arena_host ->
        if arena_host != %{} and now < arena_host["time"] do
          # test menu reset
          {is_arena_host, arena_host} =
            if arena_host["ga"] == ga do
              {1, %{arena_host | "time" => now + 30}}
            else
              {0, arena_host}
            end

          response =
            E.e(
              "response",
              E.e("IIDX32lobby", [
                E.e("host", is_arena_host, __type: "bool"),
                E.e("matching_class", arena_class, __type: "s32"),
                E.e("address", [
                  E.e("ga", arena_host["ga"], __type: "u8"),
                  E.e("gp", arena_host["gp"], __type: "u16"),
                  E.e("la", arena_host["la"], __type: "u8")
                ])
              ])
            )

          {response, arena_host}
        else
          arena_host = %{"ga" => ga, "gp" => gp, "la" => la, "time" => now + 30}

          response =
            E.e(
              "response",
              E.e("IIDX32lobby", [
                E.e("host", 1, __type: "bool"),
                E.e("matching_class", arena_class, __type: "s32"),
                E.e("address", [
                  E.e("ga", ga, __type: "u8"),
                  E.e("gp", gp, __type: "u16"),
                  E.e("la", la, __type: "u8")
                ])
              ])
            )

          {response, arena_host}
        end
      end)

    Core.send_response(conn, info, response)
  end

  def iidx32lobby_update(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("IIDX32lobby")))
  end

  def iidx32lobby_delete(conn) do
    {info, conn} = Core.process_request(conn)

    # normal reset
    State.put(@arena_host_key, %{})

    Core.send_response(conn, info, E.e("response", E.e("IIDX32lobby")))
  end

  def iidx32lobby_bplbattle_entry(conn) do
    {info, conn} = Core.process_request(conn)
    node = Core.module_node(info)

    _sp_dp = node |> XNode.child("play_style") |> text()
    arena_class = node |> XNode.child("arena_class") |> text()
    # passward
    password = node |> XNode.child("passward") |> text()
    address = XNode.child(node, "address")
    ga = address |> XNode.child("ga") |> text() |> String.split(~r/\s+/, trim: true)
    gp = address |> XNode.child("gp") |> text()
    la = address |> XNode.child("la") |> text() |> String.split(~r/\s+/, trim: true)

    now = :os.system_time(:second)

    response =
      State.update(@bpl_host_key, %{}, fn bpl_host ->
        if bpl_host != %{} and Map.has_key?(bpl_host, password) and
             now < bpl_host[password]["time"] do
          # test menu reset
          {is_bpl_host, bpl_host} =
            if bpl_host[password]["ga"] == ga do
              {1, put_in(bpl_host, [password, "time"], now + 30)}
            else
              {0, bpl_host}
            end

          response =
            E.e(
              "response",
              E.e("IIDX32lobby", [
                E.e("host", is_bpl_host, __type: "bool"),
                E.e("matching_class", arena_class, __type: "s32"),
                E.e("address", [
                  E.e("ga", bpl_host[password]["ga"], __type: "u8"),
                  E.e("gp", bpl_host[password]["gp"], __type: "u16"),
                  E.e("la", bpl_host[password]["la"], __type: "u8")
                ])
              ])
            )

          {response, bpl_host}
        else
          bpl_host =
            Map.put(bpl_host, password, %{
              "ga" => ga,
              "gp" => gp,
              "la" => la,
              "time" => now + 30
            })

          response =
            E.e(
              "response",
              E.e("IIDX32lobby", [
                E.e("host", 1, __type: "bool"),
                E.e("matching_class", arena_class, __type: "s32"),
                E.e("address", [
                  E.e("ga", ga, __type: "u8"),
                  E.e("gp", gp, __type: "u16"),
                  E.e("la", la, __type: "u8")
                ])
              ])
            )

          {response, bpl_host}
        end
      end)

    Core.send_response(conn, info, response)
  end

  def iidx32lobby_bplbattle_update(conn) do
    {info, conn} = Core.process_request(conn)
    Core.send_response(conn, info, E.e("response", E.e("IIDX32lobby")))
  end

  def iidx32lobby_bplbattle_delete(conn) do
    {info, conn} = Core.process_request(conn)
    node = Core.module_node(info)
    address = XNode.child(node, "address")
    ga = address |> XNode.child("ga") |> text() |> String.split(~r/\s+/, trim: true)

    # normal reset
    State.update(@bpl_host_key, %{}, fn bpl_host ->
      bpl_host =
        case Enum.find(bpl_host, fn {_host, entry} -> entry["ga"] == ga end) do
          {host, _entry} -> Map.delete(bpl_host, host)
          nil -> bpl_host
        end

      {bpl_host, bpl_host}
    end)

    Core.send_response(conn, info, E.e("response", E.e("IIDX32lobby")))
  end

  defp text(nil), do: nil
  defp text(%XNode{text: t}), do: t
end
