defmodule PulseWeb.MonitorLive.Index do
  use PulseWeb, :live_view

  alias Pulse.Monitoring
  alias Pulse.Monitoring.Check

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Monitoring.subscribe_to_monitors()

    {:ok,
     socket
     |> assign(:page_title, "Monitors")
     |> load_data()}
  end

  @impl true
  def handle_info({event, _payload}, socket)
      when event in [
             :monitor_created,
             :monitor_updated,
             :monitor_deleted,
             :check_recorded,
             :incident_opened,
             :incident_closed
           ] do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    monitor = Monitoring.get_monitor!(id)
    {:ok, _} = Monitoring.delete_monitor(monitor)
    Pulse.Monitoring.WorkerSupervisor.stop(monitor.id)

    {:noreply,
     socket
     |> put_flash(:info, "Monitor #{monitor.name} deleted")
     |> load_data()}
  end

  defp load_data(socket) do
    monitors = Monitoring.list_monitors()
    latest = Monitoring.latest_checks_by_monitor()
    open_incidents = Monitoring.list_open_incidents()
    open_by_monitor = Map.new(open_incidents, &{&1.monitor_id, &1})

    rows =
      Enum.map(monitors, fn monitor ->
        %{
          monitor: monitor,
          latest_check: Map.get(latest, monitor.id),
          open_incident: Map.get(open_by_monitor, monitor.id)
        }
      end)

    counts = %{
      total: length(monitors),
      up: count_by_status(rows, "up"),
      down: count_by_status(rows, ["down", "timeout", "error"]),
      pending: Enum.count(rows, &is_nil(&1.latest_check))
    }

    socket
    |> assign(:rows, rows)
    |> assign(:counts, counts)
  end

  defp count_by_status(rows, statuses) when is_list(statuses) do
    Enum.count(rows, fn row ->
      row.latest_check && row.latest_check.status in statuses
    end)
  end

  defp count_by_status(rows, status) when is_binary(status),
    do: count_by_status(rows, [status])

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Monitors
        <:subtitle>
          {@counts.total} total · {@counts.up} up · {@counts.down} down · {@counts.pending} pending
        </:subtitle>
        <:actions>
          <.button navigate={~p"/monitors/new"} icon="hero-plus" label="New monitor" />
        </:actions>
      </.header>

      <div :if={@rows == []} class="rounded-xl border border-border-1 bg-surface-default py-16">
        <.empty_state
          icon="hero-signal"
          title="No monitors yet"
          description="Add your first endpoint to start watching uptime and latency."
        >
          <:action>
            <.button navigate={~p"/monitors/new"} icon="hero-plus" label="New monitor" />
          </:action>
        </.empty_state>
      </div>

      <.simple_table
        :if={@rows != []}
        columns={["Status", "Name", "URL", "Latency", "Last check", ""]}
      >
        <tr
          :for={%{monitor: m, latest_check: c, open_incident: incident} <- @rows}
          id={"monitor-#{m.id}"}
          class="border-t border-border-1"
        >
          <td class="px-4 py-2.5 align-middle">
            <.status_badge check={c} incident={incident} enabled={m.enabled} />
          </td>
          <td class="px-4 py-2.5 align-middle text-body-3 text-text-default">
            <.link navigate={~p"/monitors/#{m.id}"} class="font-medium hover:underline">
              {m.name}
            </.link>
            <div class="text-caption-1 text-text-muted">
              every {humanize_seconds(m.interval_seconds)} · {m.method}
            </div>
          </td>
          <td class="px-4 py-2.5 align-middle text-body-3 text-text-muted truncate max-w-xs">
            {m.url}
          </td>
          <td class="px-4 py-2.5 align-middle text-body-3 text-text-default">
            {format_latency(c)}
          </td>
          <td class="px-4 py-2.5 align-middle text-body-3 text-text-muted">
            {format_time(c)}
          </td>
          <td class="px-4 py-2.5 align-middle">
            <div class="flex items-center justify-end gap-2">
              <.button
                variant="tertiary"
                size="small"
                icon="hero-pencil-square-mini"
                navigate={~p"/monitors/#{m.id}/edit"}
              />
              <.button
                variant="tertiary"
                size="small"
                icon="hero-trash-mini"
                phx-click={JS.push("delete", value: %{id: m.id})}
                data-confirm={"Delete monitor #{m.name}?"}
              />
            </div>
          </td>
        </tr>
      </.simple_table>
    </Layouts.app>
    """
  end

  attr :check, Check, default: nil
  attr :incident, :any, default: nil
  attr :enabled, :boolean, default: true

  defp status_badge(%{enabled: false} = assigns) do
    ~H"""
    <.badge variant="neutral" label="Paused" />
    """
  end

  defp status_badge(%{check: nil} = assigns) do
    ~H"""
    <.badge variant="neutral" label="Pending" />
    """
  end

  defp status_badge(%{check: %Check{status: "up"}} = assigns) do
    ~H"""
    <.badge variant="success" label="Up" />
    """
  end

  defp status_badge(%{check: %Check{status: status}} = assigns)
       when status in ["down", "timeout", "error"] do
    label =
      case status do
        "down" -> "Down"
        "timeout" -> "Timeout"
        "error" -> "Error"
      end

    assigns = assign(assigns, :label, label)

    ~H"""
    <.badge variant="error" label={@label} />
    """
  end

  defp format_latency(%Check{latency_ms: ms}) when is_integer(ms), do: "#{ms} ms"
  defp format_latency(_), do: "—"

  defp format_time(%Check{ran_at: ran_at}) when not is_nil(ran_at), do: relative_time(ran_at)
  defp format_time(_), do: "never"

  defp relative_time(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 5 -> "just now"
      diff < 60 -> "#{diff}s ago"
      diff < 3_600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3_600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp humanize_seconds(s) when s < 60, do: "#{s}s"
  defp humanize_seconds(s) when s < 3_600, do: "#{div(s, 60)}m"
  defp humanize_seconds(s), do: "#{div(s, 3_600)}h"
end
