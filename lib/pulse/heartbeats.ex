defmodule Pulse.Heartbeats do
  @moduledoc """
  Context for inbound (push-based) heartbeats. Cron jobs and the like POST to
  `/ping/:slug` on a fixed cadence; if the system doesn't see a ping within
  `expected_interval_seconds + grace_seconds`, the detector opens an incident.
  """

  import Ecto.Query

  alias Pulse.Heartbeats.{Heartbeat, Incident, Ping}
  alias Pulse.Repo

  @pubsub Pulse.PubSub
  @heartbeats_topic "heartbeats:heartbeats"

  ## Topics

  def heartbeats_topic, do: @heartbeats_topic
  def heartbeat_topic(%Heartbeat{id: id}), do: heartbeat_topic(id)
  def heartbeat_topic(id) when is_integer(id), do: "heartbeats:heartbeat:#{id}"

  def subscribe_to_heartbeats do
    Phoenix.PubSub.subscribe(@pubsub, @heartbeats_topic)
  end

  def subscribe_to_heartbeat(heartbeat_or_id) do
    Phoenix.PubSub.subscribe(@pubsub, heartbeat_topic(heartbeat_or_id))
  end

  ## Heartbeats

  def list_heartbeats do
    Repo.all(from h in Heartbeat, order_by: [asc: h.name])
  end

  def get_heartbeat!(id), do: Repo.get!(Heartbeat, id)

  def list_heartbeats_by_ids([]), do: []

  def list_heartbeats_by_ids(ids) do
    Repo.all(from h in Heartbeat, where: h.id in ^ids)
  end

  def get_heartbeat_by_slug(slug) when is_binary(slug),
    do: Repo.get_by(Heartbeat, slug: slug)

  def change_heartbeat(%Heartbeat{} = heartbeat, attrs \\ %{}) do
    Heartbeat.changeset(heartbeat, attrs)
  end

  def create_heartbeat(attrs) do
    channels = fetch_channels(attrs)

    %Heartbeat{}
    |> Heartbeat.changeset(attrs)
    |> Ecto.Changeset.put_assoc(:channels, channels)
    |> Repo.insert()
    |> tap_broadcast(:heartbeat_created)
  end

  def update_heartbeat(%Heartbeat{} = heartbeat, attrs) do
    heartbeat = Repo.preload(heartbeat, :channels)
    channels = fetch_channels(attrs)

    heartbeat
    |> Heartbeat.changeset(attrs)
    |> Ecto.Changeset.put_assoc(:channels, channels)
    |> Repo.update()
    |> tap_broadcast(:heartbeat_updated)
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

  def delete_heartbeat(%Heartbeat{} = heartbeat) do
    case Repo.delete(heartbeat) do
      {:ok, deleted} = result ->
        broadcast(@heartbeats_topic, {:heartbeat_deleted, deleted})
        result

      other ->
        other
    end
  end

  defp tap_broadcast({:ok, %Heartbeat{} = heartbeat} = result, event) do
    broadcast(@heartbeats_topic, {event, heartbeat})
    broadcast(heartbeat_topic(heartbeat), {event, heartbeat})
    result
  end

  defp tap_broadcast(other, _event), do: other

  ## Pings

  def list_recent_pings(%Heartbeat{id: id}, limit \\ 50) do
    Repo.all(
      from p in Ping,
        where: p.heartbeat_id == ^id,
        order_by: [desc: p.pinged_at],
        limit: ^limit
    )
  end

  def latest_pings_by_heartbeat do
    heartbeat_ids = Repo.all(from h in Heartbeat, select: h.id)

    Enum.reduce(heartbeat_ids, %{}, fn id, acc ->
      case Repo.one(
             from p in Ping,
               where: p.heartbeat_id == ^id,
               order_by: [desc: p.pinged_at],
               limit: 1
           ) do
        nil -> acc
        ping -> Map.put(acc, id, ping)
      end
    end)
  end

  @doc """
  Persists a ping for `heartbeat`, updates `last_pinged_at`, and closes any
  open incident in a single transaction. Broadcasts `:ping_recorded` and
  `:incident_closed` (if applicable).
  """
  def record_ping(%Heartbeat{} = heartbeat, attrs \\ %{}) do
    pinged_at = DateTime.utc_now()
    ping_attrs = Map.merge(attrs, %{heartbeat_id: heartbeat.id, pinged_at: pinged_at})

    Repo.transaction(fn ->
      {:ok, ping} =
        %Ping{}
        |> Ping.changeset(ping_attrs)
        |> Repo.insert()

      heartbeat
      |> Ecto.Changeset.change(%{last_pinged_at: pinged_at})
      |> Repo.update!()

      ping
    end)
    |> case do
      {:ok, ping} ->
        case open_incident_for(heartbeat) do
          nil -> :ok
          incident -> close_incident(incident, pinged_at)
        end

        broadcast(heartbeat_topic(heartbeat), {:ping_recorded, ping})
        broadcast(@heartbeats_topic, {:ping_recorded, ping})
        {:ok, ping}

      {:error, _} = error ->
        error
    end
  end

  ## Incidents

  def list_open_incidents do
    Repo.all(
      from i in Incident,
        where: is_nil(i.ended_at),
        order_by: [desc: i.started_at],
        preload: [:heartbeat]
    )
  end

  def list_recent_incidents(%Heartbeat{id: id}, limit \\ 20) do
    Repo.all(
      from i in Incident,
        where: i.heartbeat_id == ^id,
        order_by: [desc: i.started_at],
        limit: ^limit
    )
  end

  def open_incident_for(%Heartbeat{id: id}) do
    Repo.one(
      from i in Incident,
        where: i.heartbeat_id == ^id and is_nil(i.ended_at)
    )
  end

  def open_incident(%Heartbeat{} = heartbeat, started_at) do
    %Incident{}
    |> Incident.changeset(%{heartbeat_id: heartbeat.id, started_at: started_at})
    |> Repo.insert()
    |> case do
      {:ok, incident} = result ->
        broadcast(heartbeat_topic(heartbeat), {:incident_opened, incident})
        broadcast(@heartbeats_topic, {:incident_opened, incident})
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
        broadcast(heartbeat_topic(closed.heartbeat_id), {:incident_closed, closed})
        broadcast(@heartbeats_topic, {:incident_closed, closed})
        result

      other ->
        other
    end
  end

  ## Detector helpers

  @doc """
  Heartbeats that are currently overdue (deadline passed) AND have no open
  incident. The detector opens incidents for these.
  """
  def list_overdue(now \\ DateTime.utc_now()) do
    open_ids =
      from i in Incident,
        where: is_nil(i.ended_at),
        select: i.heartbeat_id

    from(h in Heartbeat,
      where: h.enabled == true,
      where: h.id not in subquery(open_ids)
    )
    |> Repo.all()
    |> Enum.filter(&overdue?(&1, now))
  end

  @doc """
  Computes the deadline for a heartbeat — the moment after which it counts as
  missed. Falls back to `inserted_at` if no ping has ever been received.
  """
  def deadline(%Heartbeat{} = h) do
    baseline = h.last_pinged_at || h.inserted_at
    DateTime.add(baseline, h.expected_interval_seconds + h.grace_seconds, :second)
  end

  defp overdue?(%Heartbeat{} = h, now) do
    DateTime.compare(now, deadline(h)) == :gt
  end

  defp broadcast(topic, message) do
    Phoenix.PubSub.broadcast(@pubsub, topic, message)
  end
end
