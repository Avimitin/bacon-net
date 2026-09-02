defmodule BaconNet.Tenancy.Network do
  @moduledoc "An operator network: the top-level tenancy grouping."
  use Ecto.Schema

  schema "networks" do
    field(:name, :string)
    has_many(:shops, BaconNet.Tenancy.Shop)

    timestamps(type: :utc_datetime_usec)
  end
end

defmodule BaconNet.Tenancy.Shop do
  @moduledoc "A shop (arcade location) belonging to a network."
  use Ecto.Schema

  schema "shops" do
    field(:name, :string)
    belongs_to(:network, BaconNet.Tenancy.Network)
    has_many(:cabinets, BaconNet.Tenancy.Cabinet)

    timestamps(type: :utc_datetime_usec)
  end
end

defmodule BaconNet.Tenancy.Cabinet do
  @moduledoc """
  A game cabinet, identified by its PCBID. State machine:
  pending -> permitted -> revoked (and permit may re-open a revoked cabinet).
  """
  use Ecto.Schema

  import Ecto.Changeset

  @states ["pending", "permitted", "revoked"]
  @pcbid_re ~r/^[0-9A-Za-z]{4,32}$/

  schema "cabinets" do
    field(:pcbid, :string)
    field(:state, :string, default: "pending")
    field(:label, :string)
    field(:revoked_at, :utc_datetime_usec)
    belongs_to(:shop, BaconNet.Tenancy.Shop)

    timestamps(type: :utc_datetime_usec)
  end

  def states, do: @states

  def valid_pcbid?(pcbid), do: is_binary(pcbid) and pcbid =~ @pcbid_re

  def create_changeset(cabinet, attrs) do
    cabinet
    |> cast(attrs, [:pcbid, :shop_id, :state, :label])
    |> validate_required([:pcbid, :shop_id, :state])
    |> validate_format(:pcbid, @pcbid_re)
    |> validate_inclusion(:state, @states)
    |> unique_constraint(:pcbid)
  end

  @doc "Transition to permitted; allowed from pending, revoked, or permitted (idempotent)."
  def permit_changeset(%__MODULE__{state: state} = cabinet, label)
      when state in ["pending", "revoked", "permitted"] do
    cabinet
    |> change(state: "permitted", revoked_at: nil)
    |> maybe_put_label(label)
  end

  def permit_changeset(%__MODULE__{}, _label), do: {:error, :invalid_transition}

  def revoke_changeset(%__MODULE__{} = cabinet) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    change(cabinet, state: "revoked", revoked_at: now)
  end

  defp maybe_put_label(changeset, label) when is_binary(label) and label != "" do
    put_change(changeset, :label, label)
  end

  defp maybe_put_label(changeset, _), do: changeset
end

defmodule BaconNet.Tenancy do
  @moduledoc """
  Tenancy context: networks -> shops -> cabinets.

  Every game request arrives with a body-supplied PCBID (`srcid`). That value
  only selects WHICH cabinet record to resolve — it grants nothing by itself:
  the cabinet must exist and be in the `permitted` state. Unknown PCBIDs are
  remembered as pending cabinets (under the default network/shop) so an admin
  can approve them; pending and revoked cabinets fail closed.

  The e-amusement protocol has no request signing: transport authentication
  (a private operator network or mTLS at the gateway) is the deployment
  requirement. The `BaconNet.RequestContext` built from a permitted cabinet
  carries the trusted identity for the rest of the request.
  """

  import Ecto.Query

  alias BaconNet.Repo
  alias BaconNet.Tenancy.{Cabinet, Network, Shop}

  @default_name "default"

  @doc "Cabinet with the given PCBID (shop and network preloaded), or nil."
  def get_cabinet(pcbid) when is_binary(pcbid) do
    Cabinet
    |> Repo.get_by(pcbid: pcbid)
    |> preload_assocs()
  end

  def get_cabinet(_), do: nil

  @doc """
  Resolve a body-supplied PCBID to a cabinet. Returns {:ok, cabinet} only for
  a permitted cabinet; otherwise {:error, :unknown | :pending | :revoked}.
  """
  def resolve_cabinet(pcbid) when is_binary(pcbid) do
    case get_cabinet(pcbid) do
      nil -> {:error, :unknown}
      %Cabinet{state: "permitted"} = cabinet -> {:ok, cabinet}
      %Cabinet{state: "pending"} -> {:error, :pending}
      %Cabinet{state: "revoked"} -> {:error, :revoked}
    end
  end

  def resolve_cabinet(_), do: {:error, :unknown}

  @doc """
  Remember an unknown PCBID as a pending cabinet, atomically. No-op for
  PCBIDs that already have a cabinet row in any state.
  """
  def register_pending(pcbid) when is_binary(pcbid) do
    if Cabinet.valid_pcbid?(pcbid) do
      changeset =
        Cabinet.create_changeset(%Cabinet{}, %{
          pcbid: pcbid,
          shop_id: default_shop_id(),
          state: "pending"
        })

      Repo.insert(changeset, on_conflict: :nothing, conflict_target: :pcbid)
    end

    :ok
  end

  def register_pending(_), do: :ok

  @doc """
  Permit a PCBID: transition a pending or revoked cabinet to permitted
  (clearing revoked_at), or create a permitted cabinet when none exists.
  Returns {:ok, cabinet} or {:error, :invalid_pcbid}.
  """
  def permit(pcbid, label \\ nil)

  def permit(pcbid, label) when is_binary(pcbid) do
    if Cabinet.valid_pcbid?(pcbid) do
      case get_cabinet(pcbid) do
        nil -> create_permitted(pcbid, label)
        cabinet -> transition_permit(cabinet, label)
      end
    else
      {:error, :invalid_pcbid}
    end
  end

  def permit(_, _), do: {:error, :invalid_pcbid}

  @doc "Revoke a cabinet (sets state and revoked_at; the row is kept). :ok or :not_found."
  def revoke(pcbid) when is_binary(pcbid) do
    case Repo.get_by(Cabinet, pcbid: pcbid) do
      nil ->
        :not_found

      cabinet ->
        cabinet |> Cabinet.revoke_changeset() |> Repo.update!()
        :ok
    end
  end

  def revoke(_), do: :not_found

  @doc "Delete a cabinet row entirely. :ok or :not_found."
  def delete(pcbid) when is_binary(pcbid) do
    case Repo.get_by(Cabinet, pcbid: pcbid) do
      nil -> :not_found
      cabinet -> Repo.delete!(cabinet) && :ok
    end
  end

  def delete(_), do: :not_found

  @doc "All cabinets, ordered by id, with shop and network preloaded."
  def list_cabinets do
    Cabinet
    |> order_by([c], asc: c.id)
    |> Repo.all()
    |> Repo.preload(shop: :network)
  end

  @doc "Display name for a cabinet: its label, then its shop name."
  def opname_for(pcbid) do
    case get_cabinet(pcbid) do
      nil -> nil
      %Cabinet{label: label} when is_binary(label) -> label
      %Cabinet{shop: %Shop{name: name}} -> name
      _ -> nil
    end
  end

  ## Internals

  defp create_permitted(pcbid, label) do
    changeset =
      Cabinet.create_changeset(%Cabinet{}, %{
        pcbid: pcbid,
        shop_id: default_shop_id(),
        state: "permitted",
        label: label
      })

    # A concurrent register_pending may have inserted the row; permit wins.
    case Repo.insert(changeset,
           on_conflict: [set: [state: "permitted", revoked_at: nil]],
           conflict_target: :pcbid,
           returning: true
         ) do
      {:ok, cabinet} -> {:ok, preload_assocs(cabinet)}
      {:error, _changeset} -> {:error, :invalid_pcbid}
    end
  end

  defp transition_permit(cabinet, label) do
    case Cabinet.permit_changeset(cabinet, label) do
      {:error, reason} ->
        {:error, reason}

      changeset ->
        {:ok, cabinet} = Repo.update(changeset)
        {:ok, preload_assocs(cabinet)}
    end
  end

  defp preload_assocs(nil), do: nil
  defp preload_assocs(cabinet), do: Repo.preload(cabinet, shop: :network)

  # Pending cabinets are filed under a lazily created default network/shop so
  # every cabinet has a valid tenancy path from the start.
  defp default_shop_id do
    network = get_or_create_network(@default_name)
    shop = get_or_create_shop(network.id, @default_name)
    shop.id
  end

  defp get_or_create_network(name) do
    Repo.insert(%Network{name: name}, on_conflict: :nothing, conflict_target: :name)
    Repo.get_by!(Network, name: name)
  end

  defp get_or_create_shop(network_id, name) do
    Repo.insert(%Shop{network_id: network_id, name: name},
      on_conflict: :nothing,
      conflict_target: [:network_id, :name]
    )

    Repo.get_by!(Shop, network_id: network_id, name: name)
  end
end
