defmodule BaconNet.Modules.Manage do
  @moduledoc """
  REST API for managing user data in the DB (used by the static webui).

  Generic CRUD over the TinyDB-compatible store: every table and document
  is addressable by table name and document id. Documents are returned with
  their id inlined as `_id`.
  """

  import Plug.Conn, only: [send_resp: 3, put_resp_content_type: 2]

  alias BaconNet.{Api, DB, Shop}

  @users_table "webui_users"
  @sessions_table "webui_sessions"

  def routes do
    %{
      prefix: "/manage",
      tag: "api_manage",
      handlers: [],
      api: [
        {:get, ["api", "tables"], :manage_tables},
        {:get, ["api", "cards"], :manage_cards},
        {:get, ["api", "table", :table], :manage_table_list},
        {:post, ["api", "table", :table], :manage_table_insert},
        {:delete, ["api", "table", :table], :manage_table_drop},
        {:get, ["api", "table", :table, :id], :manage_doc_get},
        {:put, ["api", "table", :table, :id], :manage_doc_replace},
        {:patch, ["api", "table", :table, :id], :manage_doc_update},
        {:delete, ["api", "table", :table, :id], :manage_doc_delete},
        {:get, ["api", "shops"], :manage_shops},
        {:post, ["api", "shops"], :manage_shop_add},
        {:post, ["api", "shops", :pcbid, "permit"], :manage_shop_permit},
        {:post, ["api", "shops", :pcbid, "revoke"], :manage_shop_revoke},
        {:delete, ["api", "shops", :pcbid], :manage_shop_delete},
        {:get, ["api", "users"], :manage_users},
        {:post, ["api", "users", :username, "ban"], :manage_user_ban},
        {:post, ["api", "users", :username, "unban"], :manage_user_unban}
      ]
    }
  end

  def manage_tables(conn, _params) do
    guard(conn, fn ->
      tables = for {name, count} <- DB.tables(), do: %{"name" => name, "count" => count}
      Api.json(conn, %{"tables" => tables})
    end)
  end

  def manage_cards(conn, _params) do
    guard(conn, fn ->
      cards =
        for {table, count} <- DB.tables(),
            count > 0,
            {id, doc} <- DB.all_with_ids(table),
            card = doc["card"],
            is_binary(card),
            reduce: %{} do
          acc -> Map.update(acc, card, [entry(table, id, doc)], &[entry(table, id, doc) | &1])
        end

      result =
        cards
        |> Enum.map(fn {card, entries} ->
          %{"card" => card, "entries" => Enum.reverse(entries)}
        end)
        |> Enum.sort_by(& &1["card"])

      Api.json(conn, %{"cards" => result})
    end)
  end

  def manage_table_list(conn, %{"table" => table}) do
    guard(conn, fn ->
      docs = for {id, doc} <- DB.all_with_ids(table), do: Map.put(doc, "_id", id)
      Api.json(conn, %{"docs" => docs})
    end)
  end

  def manage_table_insert(conn, %{"table" => table}) do
    guard(conn, fn ->
      with {:ok, doc} <- body_object(conn) do
        {id, doc} = DB.insert_with_id(table, doc)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(201, Jason.encode!(Map.put(doc, "_id", id)))
      else
        :error -> bad_request(conn)
      end
    end)
  end

  def manage_table_drop(conn, %{"table" => table}) do
    guard(conn, fn ->
      DB.drop_table(table)
      send_resp(conn, 204, "")
    end)
  end

  def manage_doc_get(conn, %{"table" => table, "id" => id}) do
    guard(conn, fn ->
      case DB.get_by_id(table, id) do
        nil -> not_found(conn)
        doc -> Api.json(conn, Map.put(doc, "_id", id))
      end
    end)
  end

  def manage_doc_replace(conn, %{"table" => table, "id" => id}) do
    guard(conn, fn ->
      with {:ok, doc} <- body_object(conn),
           :ok <- DB.replace_by_id(table, id, Map.delete(doc, "_id")) do
        Api.json(conn, Map.put(doc, "_id", id))
      else
        :error -> bad_request(conn)
        :not_found -> not_found(conn)
      end
    end)
  end

  def manage_doc_update(conn, %{"table" => table, "id" => id}) do
    guard(conn, fn ->
      with {:ok, fields} <- body_object(conn),
           :ok <- DB.update_by_id(table, id, Map.delete(fields, "_id")) do
        Api.json(conn, Map.put(DB.get_by_id(table, id), "_id", id))
      else
        :error -> bad_request(conn)
        :not_found -> not_found(conn)
      end
    end)
  end

  def manage_doc_delete(conn, %{"table" => table, "id" => id}) do
    guard(conn, fn ->
      case DB.remove_by_id(table, id) do
        :ok -> send_resp(conn, 204, "")
        :not_found -> not_found(conn)
      end
    end)
  end

  ## Shops (permitted PCBIDs)

  def manage_shops(conn, _params) do
    guard(conn, fn ->
      Api.json(conn, %{"shops" => Shop.list()})
    end)
  end

  def manage_shop_add(conn, _params) do
    guard(conn, fn ->
      with {:ok, body} <- body_object(conn),
           pcbid when is_binary(pcbid) <- body["pcbid"],
           nil <- DB.get("shop", %{"pcbid" => pcbid}),
           {:ok, doc} <- Shop.permit(pcbid, body["opname"]) do
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(201, Jason.encode!(doc))
      else
        :error -> bad_request(conn)
        nil -> bad_request(conn)
        {:error, :invalid_pcbid} -> bad_request(conn)
        %{} -> conflict(conn, "shop_exists")
      end
    end)
  end

  def manage_shop_permit(conn, %{"pcbid" => pcbid}) do
    guard(conn, fn ->
      case DB.get("shop", %{"pcbid" => pcbid}) do
        nil -> not_found(conn)
        _ -> Api.json(conn, elem(Shop.permit(pcbid), 1))
      end
    end)
  end

  def manage_shop_revoke(conn, %{"pcbid" => pcbid}) do
    guard(conn, fn ->
      case Shop.revoke(pcbid) do
        :ok -> Api.json(conn, DB.get("shop", %{"pcbid" => pcbid}))
        :not_found -> not_found(conn)
      end
    end)
  end

  def manage_shop_delete(conn, %{"pcbid" => pcbid}) do
    guard(conn, fn ->
      case Shop.delete(pcbid) do
        :ok -> send_resp(conn, 204, "")
        :not_found -> not_found(conn)
      end
    end)
  end

  ## Users (ban / unban)

  def manage_users(conn, _params) do
    guard(conn, fn ->
      users =
        for {id, user} <- DB.all_with_ids(@users_table) do
          %{
            "_id" => id,
            "username" => user["username"],
            "cards" => user["cards"] || [],
            "created_at" => user["created_at"],
            "banned" => user["banned"] == true
          }
        end

      Api.json(conn, %{"users" => users})
    end)
  end

  def manage_user_ban(conn, %{"username" => username}) do
    guard(conn, fn -> set_banned(conn, username, true) end)
  end

  def manage_user_unban(conn, %{"username" => username}) do
    guard(conn, fn -> set_banned(conn, username, false) end)
  end

  defp set_banned(conn, username, banned) do
    case DB.get(@users_table, %{"username" => username}) do
      nil ->
        not_found(conn)

      _user ->
        DB.update(@users_table, %{"banned" => banned}, %{"username" => username})

        if banned do
          # kill the user's live sessions immediately
          DB.remove(@sessions_table, %{"username" => username})
        end

        user = DB.get(@users_table, %{"username" => username})

        Api.json(conn, %{
          "username" => user["username"],
          "cards" => user["cards"] || [],
          "created_at" => user["created_at"],
          "banned" => user["banned"] == true
        })
    end
  end

  ## Internals

  defp guard(conn, fun) do
    case Api.authorize_admin(conn) do
      :ok -> fun.()
      :unauthorized -> Api.error(conn, 401, "unauthorized")
    end
  end

  defp body_object(conn) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} -> :error
      params when is_map(params) -> {:ok, params}
      _ -> :error
    end
  end

  defp entry(table, id, doc) do
    %{"table" => table, "id" => id, "name" => Api.profile_name(doc)}
  end

  defp bad_request(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(400, Jason.encode!(%{"error" => "invalid_body"}))
  end

  defp conflict(conn, reason) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(409, Jason.encode!(%{"error" => reason}))
  end

  defp not_found(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(404, Jason.encode!(%{"error" => "not_found"}))
  end
end
