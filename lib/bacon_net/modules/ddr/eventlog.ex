defmodule BaconNet.Modules.Ddr.Eventlog do
  @moduledoc "Port of modules/ddr/eventlog.py."

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local2",
      tag: "local2",
      handlers: [{"eventlog", "write", :ddr_eventlog_write}]
    }
  end

  def ddr_eventlog_write(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e("response",
        E.e("eventlog", [
          E.e("gamesession", 9_999_999, __type: "s64"),
          E.e("logsendflg", 1, __type: "s32"),
          E.e("logerrlevel", 0, __type: "s32"),
          E.e("evtidnosendflg", 0, __type: "s32")
        ])
      )

    Core.send_response(conn, info, response)
  end
end
