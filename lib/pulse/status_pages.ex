defmodule Pulse.StatusPages do
  @moduledoc """
  Context for public-facing status pages — curated views that expose the
  current status of selected monitors and heartbeats at a stable slug.
  """

  import Ecto.Query

  alias Pulse.Repo
  alias Pulse.StatusPages.StatusPage

  @pubsub Pulse.PubSub
  @status_pages_topic "status_pages:status_pages"

  def status_pages_topic, do: @status_pages_topic

  def subscribe_to_status_pages do
    Phoenix.PubSub.subscribe(@pubsub, @status_pages_topic)
  end

  def list_status_pages do
    Repo.all(from p in StatusPage, order_by: [asc: p.name], preload: [:monitors, :heartbeats])
  end

  def get_status_page!(id) do
    Repo.get!(StatusPage, id) |> Repo.preload([:monitors, :heartbeats])
  end

  def get_enabled_status_page_by_slug(slug) when is_binary(slug) do
    case Repo.get_by(StatusPage, slug: slug, enabled: true) do
      nil -> nil
      page -> Repo.preload(page, [:monitors, :heartbeats])
    end
  end

  def change_status_page(%StatusPage{} = page, attrs \\ %{}) do
    StatusPage.changeset(page, attrs)
  end

  def create_status_page(attrs) do
    monitors = fetch_monitors(attrs)
    heartbeats = fetch_heartbeats(attrs)

    %StatusPage{}
    |> StatusPage.changeset(attrs)
    |> Ecto.Changeset.put_assoc(:monitors, monitors)
    |> Ecto.Changeset.put_assoc(:heartbeats, heartbeats)
    |> Repo.insert()
    |> tap_broadcast(:status_page_created)
  end

  def update_status_page(%StatusPage{} = page, attrs) do
    page = Repo.preload(page, [:monitors, :heartbeats])
    monitors = fetch_monitors(attrs)
    heartbeats = fetch_heartbeats(attrs)

    page
    |> StatusPage.changeset(attrs)
    |> Ecto.Changeset.put_assoc(:monitors, monitors)
    |> Ecto.Changeset.put_assoc(:heartbeats, heartbeats)
    |> Repo.update()
    |> tap_broadcast(:status_page_updated)
  end

  def delete_status_page(%StatusPage{} = page) do
    case Repo.delete(page) do
      {:ok, deleted} = result ->
        broadcast({:status_page_deleted, deleted})
        result

      other ->
        other
    end
  end

  defp fetch_monitors(attrs) do
    case Map.get(attrs, "monitor_ids") || Map.get(attrs, :monitor_ids) do
      nil ->
        []

      ids when is_list(ids) ->
        ids
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.map(&to_int/1)
        |> Pulse.Monitoring.list_monitors_by_ids()
    end
  end

  defp fetch_heartbeats(attrs) do
    case Map.get(attrs, "heartbeat_ids") || Map.get(attrs, :heartbeat_ids) do
      nil ->
        []

      ids when is_list(ids) ->
        ids
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.map(&to_int/1)
        |> Pulse.Heartbeats.list_heartbeats_by_ids()
    end
  end

  defp to_int(i) when is_integer(i), do: i
  defp to_int(s) when is_binary(s), do: String.to_integer(s)

  defp tap_broadcast({:ok, %StatusPage{} = page} = result, event) do
    broadcast({event, page})
    result
  end

  defp tap_broadcast(other, _event), do: other

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(@pubsub, @status_pages_topic, message)
  end
end
