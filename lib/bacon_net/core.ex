defmodule BaconNet.Core do
  @moduledoc """
  Request/response pipeline (core_common.py counterpart).

  `process_request/1` decodes an e-amuse request conn into an info map;
  `send_response/2` encodes an XNode response back through the same
  transforms (kbin/lz77/ARC4) the request used.
  """

  require Logger

  import Plug.Conn

  alias BaconNet.{Arc4, Config, E, Kbinxml, LZ77, Shop, XNode}

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
    {body, conn} = read_body_cached(conn)
    cl = get_req_header(conn, "content-length") |> List.first()

    if !cl or body == <<>> do
      {%{}, conn}
    else
      data = binary_part(body, 0, min(byte_size(body), String.to_integer(cl)))
      compress = get_req_header(conn, "x-compress") |> List.first() || "none"

      {xml_dec, is_encrypted} =
        case get_req_header(conn, "x-eamuse-info") |> List.first() do
          nil ->
            {data, false}

          x_eamuse_info ->
            [_version, unix_time, prng] = String.split(x_eamuse_info, "-")
            key = Arc4.eamuse_key(unhex(unix_time), unhex(prng))
            {Arc4.crypt(key, data), true}
        end

      xml_dec = if compress == "lz77", do: LZ77.decode(xml_dec), else: xml_dec

      is_binxml = Kbinxml.is_binary_xml(xml_dec)
      kbin = Kbinxml.decode(xml_dec)
      root = kbin.node
      text = Kbinxml.to_text(root)

      if Config.verbose_log() do
        IO.puts("")
        IO.puts(IO.ANSI.blue() <> "REQUEST" <> IO.ANSI.reset() <> ":")
        IO.puts(text)
      end

      [model | _] = model_parts = String.split(XNode.attr(root, "model") || "", ":")
      module_node = root.children |> List.first()
      module = if module_node, do: module_node.tag
      method = module_node && XNode.attr(module_node, "method")
      command = module_node && XNode.attr(module_node, "command")
      game_version = game_version_from_software_version([XNode.attr(root, "model") | model_parts])

      {%{
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
       }, conn}
    end
  end

  @doc "The first child of the request root (the module node), or nil."
  def module_node(%{root: %XNode{children: [node | _]}}), do: node
  def module_node(_), do: nil

  @doc """
  Guard a game protocol request by shop permission. Decodes the request
  (cached for the handler) and checks the `srcid` PCBID against the shop
  registry. Returns {:ok, conn} when the shop is permitted; otherwise
  remembers the PCBID as pending, sends an error response, and returns
  {:rejected, conn}.
  """
  def guard_shop(%Plug.Conn{} = conn) do
    {info, conn} = process_request(conn)
    pcbid = info[:root] && XNode.attr(info.root, "srcid")

    if Shop.permitted?(pcbid) do
      {:ok, conn}
    else
      Shop.register_pending(pcbid)

      if pcbid do
        Logger.warning("rejecting game request from unpermitted PCBID #{pcbid}")
      else
        Logger.warning("rejecting game request without a PCBID")
      end

      {:rejected, reject_request(conn, info)}
    end
  end

  @doc "Send a protocol-level error response (status=1) for a rejected request."
  def reject_request(%Plug.Conn{} = conn, %{} = info) do
    module = Map.get(info, :module) || "services"
    send_response(conn, info, E.e("response", E.e(module, status: 1)))
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
      IO.puts(IO.ANSI.red() <> "RESPONSE" <> IO.ANSI.reset() <> ":")
      IO.puts(text)
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
        {:ok, body, conn} = read_body(conn, length: 64_000_000)
        {body, put_private(conn, :bacon_body, body)}

      body ->
        {body, conn}
    end
  end

  defp unhex(hex) do
    hex = if rem(String.length(hex), 2) == 1, do: "0" <> hex, else: hex
    Base.decode16!(String.upcase(hex))
  end

  @doc "Map a software model string to a game version (core_common.py rules)."
  def game_version_from_software_version([_full, model, _dest, _spec, _rev, ext | _]) do
    ext = String.to_integer(ext || "0")

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
