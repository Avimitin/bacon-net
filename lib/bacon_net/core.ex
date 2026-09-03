defmodule BaconNet.Core do
  @moduledoc """
  Request/response pipeline for e-amusement traffic.

  `process_request/1` decodes an e-amuse request conn into an info map;
  `send_response/2` encodes an XNode response back through the same
  transforms (kbin/lz77/ARC4) the request used.
  """

  require Logger

  import Plug.Conn

  alias BaconNet.{Arc4, Config, E, Kbinxml, LZ77, RequestContext, Shop, XNode}

  @loopback "127.0.0.1"

  def loopback, do: @loopback

  @type info :: %{
          root: XNode.t() | nil,
          text: binary | nil,
          module: binary | nil,
          method: binary | nil,
          command: binary | nil,
          model: binary | nil,
          dest: binary | nil,
          spec: binary | nil,
          rev: binary | nil,
          ext: binary | nil,
          game_version: non_neg_integer,
          compress: binary,
          is_encrypted: boolean,
          is_binxml: boolean
        }

  @doc """
  Decode the request. Returns {info, conn} (info is %{} for empty bodies).
  The decoded info is cached on the conn so guarding and the eventual
  handler only pay for the decode once.
  """
  def process_request(%Plug.Conn{} = conn) do
    case conn.private[:bacon_info] do
      nil ->
        {info, conn} = do_process_request(conn)
        {info, put_private(conn, :bacon_info, info)}

      info ->
        {info, conn}
    end
  end

  defp do_process_request(%Plug.Conn{} = conn) do
    case read_body_cached(conn) do
      {:ok, body, conn} ->
        case decode_request(conn, body) do
          {:ok, info} ->
            {info, conn}

          {:error, status, reason} ->
            Logger.warning("rejecting malformed e-amuse request: #{reason}")
            {%{}, conn |> send_resp(status, "") |> halt()}
        end

      {:error, status, conn} ->
        {%{}, conn |> send_resp(status, "") |> halt()}
    end
  end

  defp decode_request(conn, body) do
    cl = get_req_header(conn, "content-length") |> List.first()

    if !cl or body == <<>> do
      {:ok, %{}}
    else
      with {:ok, cl_int} <- parse_content_length(cl),
           {:ok, xml_dec, is_encrypted} <-
             maybe_decrypt(conn, binary_part(body, 0, min(byte_size(body), cl_int))),
           {:ok, xml_dec, compress} <- maybe_decompress(conn, xml_dec),
           {:ok, root, text, is_binxml} <- decode_xml(xml_dec) do
        if Config.verbose_log() do
          Logger.debug("REQUEST:\n" <> text)
        end

        [model | _] = model_parts = String.split(XNode.attr(root, "model") || "", ":")
        module_node = root.children |> List.first()
        module = if module_node, do: module_node.tag
        method = module_node && XNode.attr(module_node, "method")
        command = module_node && XNode.attr(module_node, "command")

        game_version =
          game_version_from_software_version([XNode.attr(root, "model") | model_parts])

        {:ok,
         %{
           root: root,
           text: text,
           module: module,
           method: method,
           command: command,
           model: model,
           dest: Enum.at(model_parts, 1),
           spec: Enum.at(model_parts, 2),
           rev: Enum.at(model_parts, 3),
           ext: Enum.at(model_parts, 4),
           game_version: game_version,
           compress: compress,
           is_encrypted: is_encrypted,
           is_binxml: is_binxml
         }}
      end
    end
  end

  defp parse_content_length(cl) do
    case Integer.parse(cl) do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> {:error, 400, "invalid content-length header #{inspect(cl)}"}
    end
  end

  defp maybe_decrypt(conn, data) do
    case get_req_header(conn, "x-eamuse-info") |> List.first() do
      nil ->
        {:ok, data, false}

      x_eamuse_info ->
        with [_version, unix_time, prng] <- String.split(x_eamuse_info, "-"),
             {:ok, time_bin} <- unhex(unix_time),
             {:ok, prng_bin} <- unhex(prng) do
          {:ok, Arc4.crypt(Arc4.eamuse_key(time_bin, prng_bin), data), true}
        else
          _ -> {:error, 400, "malformed x-eamuse-info header #{inspect(x_eamuse_info)}"}
        end
    end
  end

  defp maybe_decompress(conn, data) do
    compress = get_req_header(conn, "x-compress") |> List.first() || "none"

    if compress == "lz77" do
      decoded = LZ77.decode(data)

      if byte_size(decoded) > Config.max_decompressed_body() do
        {:error, 413, "decompressed body exceeds #{Config.max_decompressed_body()} bytes"}
      else
        {:ok, decoded, compress}
      end
    else
      {:ok, data, compress}
    end
  end

  # Kbinxml raises bare RuntimeErrors on malformed input and xmerl exits on
  # malformed text XML; every failure here is a client fault, so map any of
  # them to a 400.
  defp decode_xml(xml_dec) do
    is_binxml = Kbinxml.is_binary_xml(xml_dec)
    kbin = Kbinxml.decode(xml_dec)
    root = kbin.node
    text = Kbinxml.to_text(root)
    {:ok, root, text, is_binxml}
  rescue
    e -> {:error, 400, "invalid kbin/xml payload: #{Exception.message(e)}"}
  catch
    :exit, reason -> {:error, 400, "invalid kbin/xml payload: #{inspect(reason)}"}
  end

  @doc "The first child of the request root (the module node), or nil."
  def module_node(%{root: %XNode{children: [node | _]}}), do: node
  def module_node(_), do: nil

  @doc """
  Guard a game protocol request by cabinet permission. Decodes the request
  (cached for the handler) and resolves the body-supplied `srcid` PCBID to a
  tenancy cabinet. Returns {:ok, conn} with a `BaconNet.RequestContext`
  attached (see RequestContext.get/1) when the cabinet is permitted;
  otherwise remembers unknown PCBIDs as pending, emits a rejection telemetry
  event, sends an error response, and returns {:rejected, conn}.
  """
  def guard_shop(%Plug.Conn{} = conn) do
    {info, conn} = process_request(conn)

    # The decode already sent a 4xx for a malformed request; do not answer twice.
    if conn.halted do
      :telemetry.execute([:bacon_net, :decode, :rejected], %{count: 1}, %{})
      {:rejected, conn}
    else
      pcbid = info[:root] && XNode.attr(info.root, "srcid")

      case Shop.resolve_cabinet(pcbid) do
        {:ok, cabinet} ->
          {:ok, RequestContext.put(conn, request_context(conn, info, cabinet))}

        {:error, reason} ->
          if reason == :unknown, do: Shop.register_pending(pcbid)

          :telemetry.execute([:bacon_net, :cabinet, :rejected], %{count: 1}, %{
            pcbid: pcbid,
            reason: reason
          })

          if pcbid do
            Logger.warning("rejecting game request from #{reason} cabinet PCBID #{pcbid}")
          else
            Logger.warning("rejecting game request without a PCBID")
          end

          {:rejected, reject_request(conn, info)}
      end
    end
  end

  @doc "Send a protocol-level error response (status=1) for a rejected request."
  def reject_request(%Plug.Conn{} = conn, %{} = info) do
    module = Map.get(info, :module) || "services"
    send_response(conn, info, E.e("response", E.e(module, status: 1)))
  end

  defp request_context(conn, info, cabinet) do
    %RequestContext{
      request_id: conn.assigns[:request_id],
      network_id: cabinet.shop && cabinet.shop.network_id,
      shop_id: cabinet.shop_id,
      cabinet_id: cabinet.id,
      pcbid: cabinet.pcbid,
      game: Map.get(info, :model),
      version: Map.get(info, :game_version, 0)
    }
  end

  @doc "Encode and send an XNode response through the request's transforms."
  def send_response(%Plug.Conn{} = conn, %{} = info, %XNode{} = xml) do
    {body, headers} = prepare_response(info, xml)

    conn
    |> then(fn c -> Enum.reduce(headers, c, fn {k, v}, c -> put_resp_header(c, k, v) end) end)
    |> send_resp(200, body)
  end

  @doc "Encode an XNode response. Returns {body, headers}."
  def prepare_response(info, %XNode{} = xml) do
    {response, text} =
      if Map.get(info, :is_binxml, false) do
        {Kbinxml.encode(xml), Kbinxml.to_text(xml)}
      else
        text = Kbinxml.to_text(xml)
        {text, text}
      end

    if Config.verbose_log() do
      Logger.debug("RESPONSE:\n" <> text)
    end

    headers = [{"user-agent", "EAMUSE.Httpac/1.0"}]

    {response, headers} =
      if Config.response_compression() do
        headers = [{"x-compress", Map.get(info, :compress, "none")} | headers]

        if Map.get(info, :compress) == "lz77" do
          {LZ77.encode(response), headers}
        else
          {response, headers}
        end
      else
        {response, [{"x-compress", "none"} | headers]}
      end

    if Map.get(info, :is_encrypted, false) do
      version = 1
      unix_time = :os.system_time(:second)
      prng = :rand.uniform(0x10000) - 1

      headers = [
        {"x-eamuse-info",
         "#{version}-#{Integer.to_string(unix_time, 16) |> String.pad_leading(4, "0")}-#{Integer.to_string(prng, 16) |> String.pad_leading(2, "0")}"}
        | headers
      ]

      response = Arc4.crypt(Arc4.eamuse_key(<<unix_time::32>>, <<prng::16>>), response)
      {response, headers}
    else
      {response, headers}
    end
  end

  defp read_body_cached(conn) do
    case conn.private[:bacon_body] do
      nil ->
        case read_body(conn, length: 64_000_000) do
          {:ok, body, conn} -> {:ok, body, put_private(conn, :bacon_body, body)}
          {:more, _partial, conn} -> {:error, 413, conn}
          {:error, _reason} -> {:error, 400, conn}
        end

      body ->
        {:ok, body, conn}
    end
  end

  defp unhex(hex) do
    hex = if rem(String.length(hex), 2) == 1, do: "0" <> hex, else: hex

    case Base.decode16(String.upcase(hex)) do
      {:ok, bin} -> {:ok, bin}
      :error -> {:error, 400, "invalid hex in x-eamuse-info header"}
    end
  end

  @doc "Map a software model string to a game version (core_common.py rules)."
  def game_version_from_software_version([_full, model, _dest, _spec, _rev, ext | _]) do
    ext =
      case Integer.parse(ext || "0") do
        {n, _} -> n
        :error -> 0
      end

    cond do
      model == "LDJ" ->
        cond do
          ext >= 20_250_917_00 -> 33
          ext >= 20_241_009_00 -> 32
          ext >= 20_231_018_00 -> 31
          ext >= 20_221_017_00 -> 30
          ext >= 20_211_013_00 -> 29
          ext >= 20_201_028_00 -> 28
          ext >= 20_191_016_00 -> 27
          ext >= 20_181_107_00 -> 26
          ext >= 20_171_221_00 -> 25
          ext >= 20_161_024_00 -> 24
          ext >= 20_151_111_00 -> 23
          ext >= 20_140_917_00 -> 22
          ext >= 20_131_002_00 -> 21
          ext >= 20_120_101_00 -> 20
          true -> 0
        end

      model == "KDZ" ->
        19

      model == "JDZ" ->
        18

      model == "M32" ->
        cond do
          ext >= 20_240_313_00 -> 10
          ext >= 20_221_214_00 -> 9
          ext >= 20_210_421_00 -> 8
          ext >= 20_191_002_00 -> 7
          ext >= 20_180_727_00 -> 6
          ext >= 20_170_906_00 -> 5
          ext >= 20_170_118_00 -> 4
          ext >= 20_150_421_00 -> 3
          ext >= 20_140_214_00 -> 2
          ext >= 20_130_124_00 -> 1
          true -> 0
        end

      model == "MDX" ->
        cond do
          ext >= 20_240_612_00 and ext not in [20_240_420_69, 20_250_420_69] -> 20
          ext >= 20_190_226_00 -> 19
          true -> 0
        end

      model == "KFC" ->
        if ext >= 20_200_904_02, do: 6, else: 0

      model == "REC" ->
        1

      true ->
        0
    end
  end

  def game_version_from_software_version(_), do: 0
end
