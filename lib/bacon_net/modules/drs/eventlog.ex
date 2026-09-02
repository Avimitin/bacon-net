defmodule BaconNet.Modules.Drs.Eventlog do
  @moduledoc "Port of modules/drs/eventlog.py."

  alias BaconNet.{Core, E}

  def routes do
    %{
      prefix: "/local",
      tag: "local",
      handlers: [
        {"eventlog", "write", :drs_eventlog_write}
      ]
    }
  end

  def drs_eventlog_write(conn) do
    {info, conn} = Core.process_request(conn)

    response =
      E.e("response",
        E.e("eventlog", [
          E.e("gamesession", 9_999_999, __type: "s64"),
          E.e("logsendflg", 0, __type: "s32"),
          E.e("logerrlevel", 0, __type: "s32"),
          E.e("evtidnosendflg", 0, __type: "s32")
        ])
      )

    Core.send_response(conn, info, response)
  end
end
