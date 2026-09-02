defmodule BaconNet.RequestContext do
  @moduledoc """
  The trusted identity of one game protocol request, built by
  `BaconNet.Core.guard_shop/1` after decode.

  The e-amusement protocol has no request signing: transport authentication
  (a private operator network, or mTLS at a gateway in front of this server)
  is the deployment requirement. This context carries the trusted identity
  derived from the permitted-cabinet registry — the body-supplied `srcid`
  only selects WHICH cabinet record was resolved and grants nothing by
  itself.

  The context rides on the conn's private storage (`:bacon_request_context`),
  the same mechanism `Core.process_request/1` uses for the decoded info, so
  every game handler can reach it via `get/1` on the conn it already holds.
  """

  defstruct [:request_id, :network_id, :shop_id, :cabinet_id, :pcbid, :game, :version]

  @type t :: %__MODULE__{
          request_id: binary | nil,
          network_id: integer | nil,
          shop_id: integer | nil,
          cabinet_id: integer | nil,
          pcbid: binary,
          game: binary | nil,
          version: non_neg_integer
        }

  @key :bacon_request_context

  @doc "Store the context on the conn for downstream handlers."
  def put(%Plug.Conn{} = conn, %__MODULE__{} = ctx), do: Plug.Conn.put_private(conn, @key, ctx)

  @doc "The request context, or nil when the request was not cabinet-guarded."
  def get(%Plug.Conn{} = conn), do: conn.private[@key]
end
