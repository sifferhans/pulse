defmodule Pulse.StatusPages do
  @moduledoc """
  Context for public-facing status pages — curated views that expose the
  current status of selected monitors and heartbeats at a stable slug.
  """

  import Ecto.Query

  alias Pulse.{Heartbeats, Monitoring, Repo, Status}
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

  ## Summary / history

  @history_days 90
  @latency_points 30
  @incident_limit 20

  @uptime_windows [
    {:day, 86_400, "24h"},
    {:week, 7 * 86_400, "7d"},
    {:month, 30 * 86_400, "30d"},
    {:quarter, 90 * 86_400, "90d"}
  ]

  def uptime_windows, do: @uptime_windows

  @doc """
  Builds everything needed to render a status page: current status per item,
  90-day daily uptime bars, uptime windows, monitor latency series, and a
  combined incident timeline.

  Pure on top of the contexts — safe to call from a LiveView.
  """
  def summarize(%StatusPage{} = page, now \\ DateTime.utc_now()) do
    horizon = DateTime.add(now, -@history_days * 86_400, :second)

    latest_checks = Monitoring.latest_checks_by_monitor()
    open_heartbeat_incidents =
      Heartbeats.list_open_incidents() |> Map.new(&{&1.heartbeat_id, &1})

    monitor_summaries =
      Enum.map(page.monitors, fn monitor ->
        incidents = Monitoring.list_incidents_since(monitor, horizon)
        latency = monitor_latency_series(monitor)

        %{
          kind: :monitor,
          item: monitor,
          status: Status.monitor_status(monitor, Map.get(latest_checks, monitor.id)),
          daily: Status.daily_uptime(monitor, incidents, @history_days, now),
          windows: window_uptimes(monitor, incidents, now),
          latency_points: latency,
          incidents: incidents
        }
      end)

    heartbeat_summaries =
      Enum.map(page.heartbeats, fn heartbeat ->
        incidents = Heartbeats.list_incidents_since(heartbeat, horizon)

        %{
          kind: :heartbeat,
          item: heartbeat,
          status:
            Status.heartbeat_status(
              heartbeat,
              Map.get(open_heartbeat_incidents, heartbeat.id)
            ),
          daily: Status.daily_uptime(heartbeat, incidents, @history_days, now),
          windows: window_uptimes(heartbeat, incidents, now),
          latency_points: nil,
          incidents: incidents
        }
      end)

    overall =
      cond do
        Enum.any?(monitor_summaries, &(&1.status == :down)) -> :down
        Enum.any?(heartbeat_summaries, &(&1.status == :missed)) -> :down
        monitor_summaries == [] and heartbeat_summaries == [] -> :pending
        true -> :up
      end

    %{
      page: page,
      monitors: monitor_summaries,
      heartbeats: heartbeat_summaries,
      overall: overall,
      incidents: combined_incidents(monitor_summaries, heartbeat_summaries)
    }
  end

  defp window_uptimes(item, incidents, now) do
    Enum.map(@uptime_windows, fn {key, seconds, label} ->
      window_start =
        item.inserted_at
        |> max_dt(DateTime.add(now, -seconds, :second))

      pct = Status.uptime_percentage(incidents, window_start, now)
      {key, label, pct}
    end)
  end

  defp max_dt(a, b), do: if(DateTime.compare(a, b) == :gt, do: a, else: b)

  defp monitor_latency_series(monitor) do
    monitor
    |> Monitoring.list_recent_checks(@latency_points)
    |> Enum.reverse()
    |> Enum.map(&{&1.ran_at, &1.latency_ms})
  end

  defp combined_incidents(monitor_summaries, heartbeat_summaries) do
    monitor_entries =
      Enum.flat_map(monitor_summaries, fn %{item: monitor, incidents: incidents} ->
        Enum.map(incidents, fn i ->
          %{
            kind: :monitor,
            item_name: monitor.name,
            started_at: i.started_at,
            ended_at: i.ended_at,
            note: i.last_error
          }
        end)
      end)

    heartbeat_entries =
      Enum.flat_map(heartbeat_summaries, fn %{item: heartbeat, incidents: incidents} ->
        Enum.map(incidents, fn i ->
          %{
            kind: :heartbeat,
            item_name: heartbeat.name,
            started_at: i.started_at,
            ended_at: i.ended_at,
            note: nil
          }
        end)
      end)

    (monitor_entries ++ heartbeat_entries)
    |> Enum.sort_by(& &1.started_at, {:desc, DateTime})
    |> Enum.take(@incident_limit)
  end
end
