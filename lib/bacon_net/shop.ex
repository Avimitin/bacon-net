defmodule BaconNet.Shop do
  @moduledoc """
  Shop registry: the cabinets (PCBIDs) permitted to connect to the server.

  Shops live in the `shop` table as `%{"pcbid" => ..., "opname" => ...,
  "permitted" => bool}` documents. A game request whose `srcid` PCBID is
  unknown or not explicitly permitted (`"permitted" => true`) is rejected;
  unknown PCBIDs are remembered as pending (`"permitted" => false`) so an
  admin can approve them from the webui.
  """

  alias BaconNet.DB

  @table "shop"

  @doc "Whether a game connection from the given PCBID is allowed."
  def permitted?(pcbid) when is_binary(pcbid) do
    case DB.get(@table, %{"pcbid" => pcbid}) do
      nil -> false
      doc -> Map.get(doc, "permitted") == true
    end
  end

  def permitted?(_), do: false

  @doc """
  Remember an unknown PCBID as a pending (not yet permitted) shop so an
  admin can approve it. No-op for PCBIDs that already have a document.
  """
  def register_pending(pcbid) when is_binary(pcbid) do
    DB.insert_unless_exists(
      @table,
      %{
        "pcbid" => pcbid,
        "permitted" => false,
        "first_seen" => System.system_time(:second)
      },
      %{"pcbid" => pcbid}
    )

    :ok
  end

  def register_pending(_), do: :ok

  @doc "All shop documents, with the document id inlined as `_id`."
  def list do
    for {id, doc} <- DB.all_with_ids(@table), do: Map.put(doc, "_id", id)
  end

  @doc "Create or re-permit a shop. Returns {:ok, doc} or {:error, :invalid_pcbid}."
  def permit(pcbid, opname \\ nil)

  def permit(pcbid, opname) when is_binary(pcbid) do
    if valid_pcbid?(pcbid) do
      fields = %{"pcbid" => pcbid, "permitted" => true}

      fields =
        if is_binary(opname) and opname != "", do: Map.put(fields, "opname", opname), else: fields

      DB.upsert(@table, fields, %{"pcbid" => pcbid})
      {:ok, DB.get(@table, %{"pcbid" => pcbid})}
    else
      {:error, :invalid_pcbid}
    end
  end

  def permit(_, _), do: {:error, :invalid_pcbid}

  @doc "Revoke a shop's permission (the document is kept). Returns :ok or :not_found."
  def revoke(pcbid) when is_binary(pcbid) do
    case DB.get(@table, %{"pcbid" => pcbid}) do
      nil ->
        :not_found

      _doc ->
        DB.update(@table, %{"permitted" => false}, %{"pcbid" => pcbid})
        :ok
    end
  end

  @doc "Delete a shop document entirely. Returns :ok or :not_found."
  def delete(pcbid) when is_binary(pcbid) do
    case DB.get(@table, %{"pcbid" => pcbid}) do
      nil ->
        :not_found

      _doc ->
        DB.remove(@table, %{"pcbid" => pcbid})
        :ok
    end
  end

  defp valid_pcbid?(pcbid), do: pcbid =~ ~r/^[0-9A-Za-z]{4,32}$/
end
