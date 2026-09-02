defmodule BaconNet.Shop do
  @moduledoc """
  Shop registry: the cabinets (PCBIDs) permitted to connect to the server.

  Rewritten on top of `BaconNet.Tenancy`: shops are now real `shops` rows
  grouped under `networks`, and the unit of permission is a `cabinets` row
  keyed by PCBID with a state of pending/permitted/revoked. A game request
  whose `srcid` PCBID is unknown, pending, or revoked is rejected; unknown
  PCBIDs are remembered as pending cabinets so an admin can approve them
  from the webui.

  This module keeps the pre-tenancy function shapes (`permitted?/1`,
  `register_pending/1`, `list/0`, `permit/2`, `revoke/1`, `delete/1`) and
  document-style maps (`%{"pcbid" => ..., "permitted" => bool, ...}`) so the
  manage API and webui keep working unchanged.
  """

  alias BaconNet.Tenancy
  alias BaconNet.Tenancy.Cabinet

  @doc "Whether a game connection from the given PCBID is allowed."
  def permitted?(pcbid) when is_binary(pcbid) do
    match?({:ok, _}, Tenancy.resolve_cabinet(pcbid))
  end

  def permitted?(_), do: false

  @doc "Resolve a body-supplied PCBID to a permitted cabinet (see Tenancy.resolve_cabinet/1)."
  defdelegate resolve_cabinet(pcbid), to: Tenancy

  @doc "Cabinet with the given PCBID (shop/network preloaded), or nil."
  defdelegate get_cabinet(pcbid), to: Tenancy

  @doc """
  Remember an unknown PCBID as a pending cabinet so an admin can approve it.
  Atomic no-op for PCBIDs that already have a cabinet row.
  """
  defdelegate register_pending(pcbid), to: Tenancy

  @doc "All cabinets as document-style maps, with the row id inlined as `_id`."
  def list do
    for cabinet <- Tenancy.list_cabinets(), do: to_doc(cabinet)
  end

  @doc """
  Create or re-permit a cabinet (permit requires a pending or revoked state
  for existing rows and is idempotent for permitted ones).
  Returns {:ok, doc} or {:error, :invalid_pcbid}.
  """
  def permit(pcbid, opname \\ nil) do
    case Tenancy.permit(pcbid, opname) do
      {:ok, cabinet} -> {:ok, to_doc(cabinet)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Revoke a cabinet's permission (the row is kept). Returns :ok or :not_found."
  defdelegate revoke(pcbid), to: Tenancy

  @doc "Delete a cabinet row entirely. Returns :ok or :not_found."
  defdelegate delete(pcbid), to: Tenancy

  @doc "Display name for a PCBID: cabinet label, shop name, or nil."
  defdelegate opname_for(pcbid), to: Tenancy

  @doc false
  def to_doc(%Cabinet{} = cabinet) do
    %{
      "_id" => cabinet.id,
      "pcbid" => cabinet.pcbid,
      "permitted" => cabinet.state == "permitted",
      "state" => cabinet.state,
      "opname" => cabinet.label || shop_name(cabinet),
      "first_seen" => cabinet.inserted_at && DateTime.to_unix(cabinet.inserted_at),
      "revoked_at" => cabinet.revoked_at
    }
  end

  defp shop_name(%Cabinet{shop: %Ecto.Association.NotLoaded{}}), do: nil
  defp shop_name(%Cabinet{shop: nil}), do: nil
  defp shop_name(%Cabinet{shop: shop}), do: shop.name
end
