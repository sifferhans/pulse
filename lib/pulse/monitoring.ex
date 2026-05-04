defmodule Pulse.Monitoring do
  @moduledoc """
  Context for outbound uptime monitors and the HTTP probes they produce.
  """

  import Ecto.Query

  alias Pulse.Monitoring.{Check, Incident, Monitor}
  alias Pulse.Repo

  @pubsub Pulse.PubSub
  @monitors_topic "monitoring:monitors"

  ## Topics

  def monitors_topic, do: @monitors_topic
  def monitor_topic(%Monitor{id: id}), do: monitor_topic(id)
  def monitor_topic(id) when is_integer(id), do: "monitoring:monitor:#{id}"

  def subscribe_to_monitors do
    Phoenix.PubSub.subscribe(@pubsub, @monitors_topic)
  end

  def subscribe_to_monitor(monitor_or_id) do
    Phoenix.PubSub.subscribe(@pubsub, monitor_topic(monitor_or_id))
  end

  ## Monitors

  def list_monitors do
    Repo.all(from m in Monitor, order_by: [asc: m.name])
  end

  def list_enabled_monitors do
    Repo.all(from m in Monitor, where: m.enabled == true)
  end

  def get_monitor!(id), do: Repo.get!(Monitor, id)

  def list_monitors_by_ids([]), do: []

  def list_monitors_by_ids(ids) do
    Repo.all(from m in Monitor, where: m.id in ^ids)
  end

  def change_monitor(%Monitor{} = monitor, attrs \\ %{}) do
    Monitor.changeset(monitor, attrs)
  end

  def create_monitor(attrs) do
    channels = fetch_channels(attrs)

    %Monitor{}
    |> Monitor.changeset(attrs)
    |> Ecto.Changeset.put_assoc(:channels, channels)
    |> Repo.insert()
    |> tap_broadcast(:monitor_created)
  end

  def update_monitor(%Monitor{} = monitor, attrs) do
    monitor = Repo.preload(monitor, :channels)
    channels = fetch_channels(attrs)

    monitor
    |> Monitor.changeset(attrs)
    |> Ecto.Changeset.put_assoc(:channels, channels)
    |> Repo.update()
    |> tap_broadcast(:monitor_updated)
  end

  defp fetch_channels(attrs) do
    case Map.get(attrs, "channel_ids") || Map.get(attrs, :channel_ids) do
      nil ->
        []

      ids when is_list(ids) ->
        ids
        |> Enum.reject(&(&1 in [nil, ""]))
        |> Enum.map(&to_int/1)
        |> Pulse.Notifications.list_channels_by_ids()
    end
  end

  defp to_int(i) when is_integer(i), do: i
  defp to_int(s) when is_binary(s), do: String.to_integer(s)

  def delete_monitor(%Monitor{} = monitor) do
    case Repo.delete(monitor) do
      {:ok, deleted} = result ->
        broadcast(@monitors_topic, {:monitor_deleted, deleted})
        result

      other ->
        other
    end
  end

  defp tap_broadcast({:ok, %Monitor{} = monitor} = result, event) do
    broadcast(@monitors_topic, {event, monitor})
    broadcast(monitor_topic(monitor), {event, monitor})
    result
  end

  defp tap_broadcast(other, _event), do: other

  ## Checks

  def list_recent_checks(%Monitor{id: monitor_id}, limit \\ 50) do
    Repo.all(
      from c in Check,
        where: c.monitor_id == ^monitor_id,
        order_by: [desc: c.ran_at],
        limit: ^limit
    )
  end

  def latest_check(%Monitor{id: monitor_id}) do
    Repo.one(
      from c in Check,
        where: c.monitor_id == ^monitor_id,
        order_by: [desc: c.ran_at],
        limit: 1
    )
  end

  def latest_checks_by_monitor do
    monitor_ids = Repo.all(from m in Monitor, select: m.id)

    Enum.reduce(monitor_ids, %{}, fn id, acc ->
      case Repo.one(
             from c in Check,
               where: c.monitor_id == ^id,
               order_by: [desc: c.ran_at],
               limit: 1
           ) do
        nil -> acc
        check -> Map.put(acc, id, check)
      end
    end)
  end

  def record_check(attrs) do
    %Check{}
    |> Check.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, check} = result ->
        broadcast(monitor_topic(check.monitor_id), {:check_recorded, check})
        broadcast(@monitors_topic, {:check_recorded, check})
        result

      other ->
        other
    end
  end

  ## Incidents

  def list_open_incidents do
    Repo.all(
      from i in Incident,
        where: is_nil(i.ended_at),
        order_by: [desc: i.started_at],
        preload: [:monitor]
    )
  end

  def list_incidents_since(%Monitor{id: monitor_id}, %DateTime{} = since) do
    Repo.all(
      from i in Incident,
        where: i.monitor_id == ^monitor_id,
        where: is_nil(i.ended_at) or i.ended_at >= ^since,
        order_by: [asc: i.started_at]
    )
  end

  def list_recent_incidents(%Monitor{id: monitor_id}, limit \\ 20) do
    Repo.all(
      from i in Incident,
        where: i.monitor_id == ^monitor_id,
        order_by: [desc: i.started_at],
        limit: ^limit
    )
  end

  def open_incident_for(%Monitor{id: monitor_id}) do
    Repo.one(
      from i in Incident,
        where: i.monitor_id == ^monitor_id and is_nil(i.ended_at)
    )
  end

  def open_incident(%Monitor{} = monitor, started_at, last_error) do
    %Incident{}
    |> Incident.changeset(%{
      monitor_id: monitor.id,
      started_at: started_at,
      last_error: last_error
    })
    |> Repo.insert()
    |> case do
      {:ok, incident} = result ->
        broadcast(monitor_topic(monitor), {:incident_opened, incident})
        broadcast(@monitors_topic, {:incident_opened, incident})
        result

      other ->
        other
    end
  end

  def close_incident(%Incident{} = incident, ended_at) do
    incident
    |> Incident.changeset(%{ended_at: ended_at})
    |> Repo.update()
    |> case do
      {:ok, closed} = result ->
        broadcast(monitor_topic(closed.monitor_id), {:incident_closed, closed})
        broadcast(@monitors_topic, {:incident_closed, closed})
        result

      other ->
        other
    end
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(@pubsub, topic, message)
  end
end
