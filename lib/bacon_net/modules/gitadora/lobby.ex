defmodule BaconNet.Modules.Gitadora.Lobby do
  @moduledoc "Port of modules/gitadora/lobby.py."

  alias BaconNet.{Core, E, State, XNode}

  def routes do
    %{
      prefix: "/lobby",
      tag: "lobby",
      handlers: [
        {"lobby", "request", :gitadora_lobby_request}
      ]
    }
  end

  def gitadora_lobby_request(conn) do
    {info, conn} = Core.process_request(conn)

    root = Core.module_node(info).children |> List.first()
    address_ip = root |> XNode.child("address") |> XNode.child("ip") |> Map.get(:text)
    check_attestid = root |> XNode.child("check") |> XNode.child("attestid") |> Map.get(:text)

    host = State.get(:gitadora_lobby_host, %{})

    response =
      if host != %{} do
        resp =
          if host["ip"] != address_ip do
            E.e(
              "response",
              E.e(
                "lobby",
                E.e(
                  "lobbydata",
                  E.e("candidate", [
                    E.e(
                      "address",
                      E.e("ip", host["ip"], __type: "str")
                    ),
                    E.e(
                      "check",
                      E.e("attestid", host["attestid"], __type: "str")
                    )
                  ])
                )
              )
            )
          else
            E.e("response", E.e("lobby"))
          end

        State.put(:gitadora_lobby_host, %{})

        resp
      else
        State.put(:gitadora_lobby_host, %{"ip" => address_ip, "attestid" => check_attestid})

        E.e("response", E.e("lobby"))
      end

    Core.send_response(conn, info, response)
  end
end
