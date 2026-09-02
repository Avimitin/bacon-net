defmodule BaconNet.Router do
  @moduledoc """
  HTTP entry point (pyeamu.py + modules/__init__.py counterpart).
  """

  use Plug.Router

  alias BaconNet.{Card, Config, Core, E, Registry}

  plug(:match)

  plug(BaconNet.Plugs.RequestId)

  plug(BaconNet.Plugs.Metrics)

  plug(BaconNet.Plugs.CORS)

  plug(BaconNet.Plugs.Webui)

  plug(Plug.Parsers,
    parsers: [:multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(:dispatch)

  ## services.get (pyeamu.py)

  post "/core" do
    services_get(conn)
  end

  post "/core/:gameinfo/services/get" do
    services_get(conn)
  end

  ## Slashless forwarder (modules/__init__.py)

  post "/fwdr" do
    conn = fetch_query_params(conn)
    params = conn.query_params
    model = params["model"] || ""
    f = params["f"]

    {module, method} =
      if f do
        case String.split(f, ".", parts: 2) do
          [m, meth] -> {m, meth}
          _ -> {params["module"], params["method"]}
        end
      else
        {params["module"], params["method"]}
      end

    name = String.downcase("#{module}_#{method}")

    case Core.guard_shop(conn) do
      {:ok, conn} ->
        case Registry.dispatch_by_name(conn, name) do
          :not_found ->
            forward_game_specific(conn, model, module, method)

          conn ->
            conn
        end

      {:rejected, conn} ->
        conn
    end
  end

  ## Misc endpoints

  get "/" do
    conn
    |> put_resp_header("location", "/webui/")
    |> send_resp(302, "")
  end

  ## Ops endpoints (no auth: they reveal nothing)

  get "/healthz" do
    send_resp(conn, 200, "ok\n")
  end

  get "/readyz" do
    try do
      case Config.readiness_check().() do
        {:ok, _} -> send_resp(conn, 200, "ok\n")
        _ -> send_resp(conn, 503, "not ready\n")
      end
    rescue
      _ -> send_resp(conn, 503, "not ready\n")
    end
  end

  get "/metrics" do
    case BaconNet.Api.authorize_admin(conn) do
      :ok ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, BaconNet.Telemetry.render())

      :unauthorized ->
        BaconNet.Api.error(conn, 401, "unauthorized")
    end
  end

  get "/config" do
    json(conn, Config.settings())
  end

  get "/conv/:card" do
    card = String.upcase(card)

    card =
      card
      |> String.replace("I", "1")
      |> String.replace("O", "0")
      |> String.replace("Q", "0")
      |> String.replace("V", "U")

    if String.starts_with?(card, "E004") or String.starts_with?(card, "012E") do
      uid =
        card
        |> :binary.bin_to_list()
        |> Enum.filter(&(&1 in ~c"0123456789ABCDEF"))
        |> IO.iodata_to_binary()

      json(conn, %{"uid" => uid, "konami_id" => Card.to_konami_id(uid)})
    else
      valid = Card.valid_characters() |> :binary.bin_to_list()

      kid =
        card |> :binary.bin_to_list() |> Enum.filter(&(&1 in valid)) |> IO.iodata_to_binary()

      json(conn, %{"uid" => Card.to_uid(kid), "konami_id" => kid})
    end
  end

  ## Game protocol routes

  post "/:prefix/:gameinfo/:mod/:method" do
    conn = fetch_query_params(conn)

    if Registry.game_route?("/#{prefix}", mod, method) do
      case Core.guard_shop(conn) do
        {:ok, conn} -> Registry.dispatch(conn, "/#{prefix}", mod, method)
        {:rejected, conn} -> conn
      end
    else
      case Registry.dispatch_api(conn, :post, "/#{prefix}", [gameinfo, mod, method]) do
        nil -> send_resp(conn, 404, "")
        conn -> conn
      end
    end
  end

  ## API (JSON) routes

  get "/:prefix/*rest" do
    case Registry.dispatch_api(conn, :get, "/#{prefix}", rest) do
      nil -> send_resp(conn, 404, "")
      conn -> conn
    end
  end

  patch "/:prefix/*rest" do
    case Registry.dispatch_api(conn, :patch, "/#{prefix}", rest) do
      nil -> send_resp(conn, 404, "")
      conn -> conn
    end
  end

  put "/:prefix/*rest" do
    case Registry.dispatch_api(conn, :put, "/#{prefix}", rest) do
      nil -> send_resp(conn, 404, "")
      conn -> conn
    end
  end

  delete "/:prefix/*rest" do
    case Registry.dispatch_api(conn, :delete, "/#{prefix}", rest) do
      nil -> send_resp(conn, 404, "")
      conn -> conn
    end
  end

  match "/:prefix/*rest", via: :post do
    case Registry.dispatch_api(conn, :post, "/#{prefix}", rest) do
      nil -> send_resp(conn, 404, "")
      conn -> conn
    end
  end

  match _ do
    send_resp(conn, 404, "")
  end

  ## Internals

  defp services_get(conn) do
    conn = fetch_query_params(conn)

    case Core.guard_shop(conn) do
      {:ok, conn} -> do_services_get(conn)
      {:rejected, conn} -> conn
    end
  end

  defp do_services_get(conn) do
    {info, conn} = Core.process_request(conn)
    params = conn.query_params

    request_address = "#{conn.host}:#{conn.port}:#{Config.port()}"

    url_slashless =
      params["f"] == "services.get" or
        (params["module"] == "services" and params["method"] == "get")

    items =
      for %{tag: tag, prefix: prefix} <- Registry.services() do
        pre = if url_slashless, do: "/fwdr", else: prefix
        E.e("item", name: tag, url: "http://#{request_address}#{pre}")
      end

    keepalive_params = [
      pa: Core.loopback(),
      ia: Core.loopback(),
      ga: Core.loopback(),
      ma: Core.loopback(),
      t1: 2,
      t2: 10
    ]

    items =
      items ++
        [
          E.e("item",
            name: "keepalive",
            url: "http://#{Core.loopback()}/keepalive?#{Plug.Conn.Query.encode(keepalive_params)}"
          ),
          E.e("item", name: "ntp", url: "ntp://pool.ntp.org/")
        ]

    response =
      E.e(
        "response",
        E.e("services", items, expire: 10800, mode: "operation", product_domain: 1)
      )

    Core.send_response(conn, info, response)
  end

  defp forward_game_specific(conn, model, module, method) do
    game_code = model |> String.split(":") |> hd()

    result =
      cond do
        game_code == "MDX" and String.starts_with?(module, "eventlo") ->
          Registry.dispatch_by_name(conn, "ddr_#{module}_#{method}")

        game_code == "REC" ->
          Registry.dispatch_by_name(conn, "drs_#{module}_#{method}")

        game_code == "KFC" and module == "eventlog" ->
          Registry.dispatch_by_name(conn, "sdvx_#{module}_#{method}")

        game_code == "KFC" ->
          sdvx_ver = method |> String.replace(~r/\D/, "")
          method_name = String.replace(method, ~r/\d/, "")
          Registry.dispatch_by_name(conn, "#{module}_#{method_name}", sdvx_ver)

        game_code == "M32" and module == "lobby" ->
          Registry.dispatch_by_name(conn, "gitadora_#{module}_#{method}")

        game_code == "M32" ->
          gd_module = String.split(module, "_")

          Registry.dispatch_by_name(
            conn,
            "gitadora_#{List.last(gd_module)}_#{method}",
            hd(gd_module)
          )

        true ->
          :not_found
      end

    case result do
      :not_found ->
        IO.puts("Try URL Slash 1 (On) if this game is supported.")
        send_resp(conn, 404, "")

      conn ->
        conn
    end
  end

  defp json(conn, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(data))
  end
end
