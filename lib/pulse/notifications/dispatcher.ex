defmodule Pulse.Notifications.Dispatcher do
  @moduledoc """
  Subscribes to monitoring + heartbeats PubSub topics and fans out incident
  open/close events to each subject's notification channels. Sending happens
  off-process via `Pulse.Notifications.TaskSupervisor` so the dispatcher never
  blocks on HTTP.
  """

  use GenServer

  require Logger

  alias Pulse.{Heartbeats, Monitoring, Notifications, Repo}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Pulse.PubSub, Monitoring.monitors_topic())
    Phoenix.PubSub.subscribe(Pulse.PubSub, Heartbeats.heartbeats_topic())
    {:ok, %{}}
  end

  @impl true
  def handle_info({event, %Monitoring.Incident{} = incident}, state)
      when event in [:incident_opened, :incident_closed] do
    monitor =
      Monitoring.get_monitor!(incident.monitor_id)
      |> Repo.preload(:channels)

    fan_out(monitor.channels, format_monitor(monitor, incident, event))
    {:noreply, state}
  end

  def handle_info({event, %Heartbeats.Incident{} = incident}, state)
      when event in [:incident_opened, :incident_closed] do
    heartbeat =
      Heartbeats.get_heartbeat!(incident.heartbeat_id)
      |> Repo.preload(:channels)

    fan_out(heartbeat.channels, format_heartbeat(heartbeat, incident, event))
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp fan_out(channels, message) do
    for channel <- channels, channel.enabled do
      Task.Supervisor.start_child(Pulse.Notifications.TaskSupervisor, fn ->
        deliver(channel, message)
      end)
    end
  end

  defp deliver(channel, message) do
    case Notifications.send_message(channel, message) do
      {:ok, _} ->
        :ok

      other ->
        Logger.warning(
          "Notification to channel #{channel.id} (#{channel.kind}) failed: #{inspect(other)}"
        )
    end
  end

  defp format_monitor(monitor, incident, :incident_opened) do
    error = incident.last_error || "no response details"
    "🔴 Monitor \"#{monitor.name}\" is DOWN — #{error}\n#{monitor.method} #{monitor.url}"
  end

  defp format_monitor(monitor, incident, :incident_closed) do
    duration = humanize_seconds(DateTime.diff(incident.ended_at, incident.started_at, :second))
    "✅ Monitor \"#{monitor.name}\" recovered after #{duration}"
  end

  defp format_heartbeat(heartbeat, _incident, :incident_opened) do
    "🔴 Heartbeat \"#{heartbeat.name}\" MISSED — expected every #{humanize_seconds(heartbeat.expected_interval_seconds)}"
  end

  defp format_heartbeat(heartbeat, incident, :incident_closed) do
    duration = humanize_seconds(DateTime.diff(incident.ended_at, incident.started_at, :second))
    "✅ Heartbeat \"#{heartbeat.name}\" recovered after #{duration}"
  end

  defp humanize_seconds(s) when s < 60, do: "#{s}s"
  defp humanize_seconds(s) when s < 3_600, do: "#{div(s, 60)}m"
  defp humanize_seconds(s), do: "#{div(s, 3_600)}h"
end
