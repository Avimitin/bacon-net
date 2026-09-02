defmodule BaconNet.Plugs.Webui do
  @moduledoc """
  Serves the static webui (frontend/dist) under /webui.

  `Plug.Static` options are resolved at runtime so the directory can be
  overridden with Application env (`:webui_dir`, see config/runtime.exs).
  """

  import Plug.Conn

  alias BaconNet.Config

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{request_path: "/webui"} = conn, _opts) do
    conn
    |> put_resp_header("location", "/webui/")
    |> send_resp(301, "")
    |> halt()
  end

  def call(%Plug.Conn{request_path: "/webui/"} = conn, _opts) do
    serve(%{conn | request_path: "/webui/index.html", path_info: ["webui", "index.html"]})
  end

  def call(%Plug.Conn{request_path: "/webui/" <> _} = conn, _opts), do: serve(conn)

  def call(conn, _opts), do: conn

  defp serve(conn) do
    dir = Config.webui_dir()

    opts =
      case :persistent_term.get({__MODULE__, dir}, nil) do
        nil ->
          opts = Plug.Static.init(at: "/webui", from: dir)
          :persistent_term.put({__MODULE__, dir}, opts)
          opts

        opts ->
          opts
      end

    Plug.Static.call(conn, opts)
  end
end
