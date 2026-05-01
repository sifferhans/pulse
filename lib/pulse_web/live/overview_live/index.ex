defmodule PulseWeb.OverviewLive.Index do
  use PulseWeb, :live_view

  alias Pulse.{Heartbeats, Monitoring}
  alias Pulse.Heartbeats.Heartbeat
  alias Pulse.Monitoring.Check

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Monitoring.subscribe_to_monitors()
      Heartbeats.subscribe_to_heartbeats()
    end

    {:ok,
     socket
     |> assign(:page_title, "Pulse")
     |> load_data()}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_event("delete_monitor", %{"id" => id}, socket) do
    monitor = Monitoring.get_monitor!(id)
    {:ok, _} = Monitoring.delete_monitor(monitor)
    Pulse.Monitoring.WorkerSupervisor.stop(monitor.id)

    {:noreply,
     socket
     |> put_flash(:info, "Monitor #{monitor.name} deleted")
     |> load_data()}
  end

  def handle_event("delete_heartbeat", %{"id" => id}, socket) do
    heartbeat = Heartbeats.get_heartbeat!(id)
    {:ok, _} = Heartbeats.delete_heartbeat(heartbeat)

    {:noreply,
     socket
     |> put_flash(:info, "Heartbeat #{heartbeat.name} deleted")
     |> load_data()}
  end

  defp load_data(socket) do
    socket
    |> assign_monitors()
    |> assign_heartbeats()
  end

  defp assign_monitors(socket) do
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
      up: count_check_by_status(rows, "up"),
      down: count_check_by_status(rows, ["down", "timeout", "error"]),
      pending: Enum.count(rows, &is_nil(&1.latest_check))
    }

    socket
    |> assign(:monitor_rows, rows)
    |> assign(:monitor_counts, counts)
  end

  defp assign_heartbeats(socket) do
    heartbeats = Heartbeats.list_heartbeats()
    open_incidents = Heartbeats.list_open_incidents()
    open_by_heartbeat = Map.new(open_incidents, &{&1.heartbeat_id, &1})

    rows =
      Enum.map(heartbeats, fn heartbeat ->
        open = Map.get(open_by_heartbeat, heartbeat.id)

        %{
          heartbeat: heartbeat,
          open_incident: open,
          status: heartbeat_status(heartbeat, open)
        }
      end)

    counts = %{
      total: length(heartbeats),
      alive: Enum.count(rows, &(&1.status == :alive)),
      missed: Enum.count(rows, &(&1.status == :missed)),
      pending: Enum.count(rows, &(&1.status == :pending))
    }

    socket
    |> assign(:heartbeat_rows, rows)
    |> assign(:heartbeat_counts, counts)
  end

  defp count_check_by_status(rows, statuses) when is_list(statuses) do
    Enum.count(rows, fn row ->
      row.latest_check && row.latest_check.status in statuses
    end)
  end

  defp count_check_by_status(rows, status) when is_binary(status),
    do: count_check_by_status(rows, [status])

  defp heartbeat_status(%Heartbeat{enabled: false}, _), do: :paused
  defp heartbeat_status(%Heartbeat{}, %{} = _open), do: :missed
  defp heartbeat_status(%Heartbeat{last_pinged_at: nil}, _), do: :pending
  defp heartbeat_status(%Heartbeat{}, _), do: :alive

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section class="space-y-3">
        <div class="flex items-center justify-between gap-4">
          <div class="flex flex-col">
            <h2 class="text-title-1 font-semibold text-text-default">Monitors</h2>
            <span :if={@monitor_counts.total > 0} class="text-caption-1 text-text-muted">
              {@monitor_counts.up} up · {@monitor_counts.down} down · {@monitor_counts.pending} pending
            </span>
          </div>
          <.button
            :if={@monitor_rows != []}
            navigate={~p"/monitors/new"}
            icon="hero-plus"
            label="New monitor"
          />
        </div>

        <div
          :if={@monitor_rows == []}
          class="rounded-xl border border-border-1 bg-surface-default py-12"
        >
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
          :if={@monitor_rows != []}
          columns={["Status", "Name", "URL", "Latency", "Last check", ""]}
        >
          <tr
            :for={%{monitor: m, latest_check: c, open_incident: incident} <- @monitor_rows}
            id={"monitor-#{m.id}"}
            class="border-t border-border-1"
          >
            <td class="px-4 py-2.5 align-middle">
              <.monitor_status_badge check={c} incident={incident} enabled={m.enabled} />
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
              {format_time(c && c.ran_at)}
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
                  phx-click={JS.push("delete_monitor", value: %{id: m.id})}
                  data-confirm={"Delete monitor #{m.name}?"}
                />
              </div>
            </td>
          </tr>
        </.simple_table>
      </section>

      <section class="space-y-3">
        <div class="flex items-center justify-between gap-4">
          <div class="flex flex-col">
            <h2 class="text-title-1 font-semibold text-text-default">Heartbeats</h2>
            <span :if={@heartbeat_counts.total > 0} class="text-caption-1 text-text-muted">
              {@heartbeat_counts.alive} alive · {@heartbeat_counts.missed} missed · {@heartbeat_counts.pending} pending
            </span>
          </div>
          <.button
            :if={@heartbeat_rows != []}
            navigate={~p"/heartbeats/new"}
            icon="hero-plus"
            label="New heartbeat"
          />
        </div>

        <div
          :if={@heartbeat_rows == []}
          class="rounded-xl border border-border-1 bg-surface-default py-12"
        >
          <.empty_state
            icon="hero-heart"
            title="No heartbeats yet"
            description="Create one and point a cron job at the URL to start watching it."
          >
            <:action>
              <.button navigate={~p"/heartbeats/new"} icon="hero-plus" label="New heartbeat" />
            </:action>
          </.empty_state>
        </div>

        <.simple_table
          :if={@heartbeat_rows != []}
          columns={["Status", "Name", "Expected", "Last ping", ""]}
        >
          <tr
            :for={%{heartbeat: h, status: status} <- @heartbeat_rows}
            id={"heartbeat-#{h.id}"}
            class="border-t border-border-1"
          >
            <td class="px-4 py-2.5 align-middle">
              <.heartbeat_status_badge status={status} />
            </td>
            <td class="px-4 py-2.5 align-middle text-body-3 text-text-default">
              <.link navigate={~p"/heartbeats/#{h.id}"} class="font-medium hover:underline">
                {h.name}
              </.link>
              <div class="text-caption-1 text-text-muted">
                grace {humanize_seconds(h.grace_seconds)}
              </div>
            </td>
            <td class="px-4 py-2.5 align-middle text-body-3 text-text-muted">
              {humanize_seconds(h.expected_interval_seconds)}
            </td>
            <td class="px-4 py-2.5 align-middle text-body-3 text-text-muted">
              {format_time(h.last_pinged_at)}
            </td>
            <td class="px-4 py-2.5 align-middle">
              <div class="flex items-center justify-end gap-2">
                <.button
                  variant="tertiary"
                  size="small"
                  icon="hero-pencil-square-mini"
                  navigate={~p"/heartbeats/#{h.id}/edit"}
                />
                <.button
                  variant="tertiary"
                  size="small"
                  icon="hero-trash-mini"
                  phx-click={JS.push("delete_heartbeat", value: %{id: h.id})}
                  data-confirm={"Delete heartbeat #{h.name}?"}
                />
              </div>
            </td>
          </tr>
        </.simple_table>
      </section>
    </Layouts.app>
    """
  end

  attr :check, Check, default: nil
  attr :incident, :any, default: nil
  attr :enabled, :boolean, default: true

  defp monitor_status_badge(%{enabled: false} = assigns),
    do: ~H|<.badge variant="neutral" label="Paused" />|

  defp monitor_status_badge(%{check: nil} = assigns),
    do: ~H|<.badge variant="neutral" label="Pending" />|

  defp monitor_status_badge(%{check: %Check{status: "up"}} = assigns),
    do: ~H|<.badge variant="success" label="Up" />|

  defp monitor_status_badge(%{check: %Check{status: status}} = assigns)
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

  attr :status, :atom, required: true

  defp heartbeat_status_badge(%{status: :alive} = assigns),
    do: ~H|<.badge variant="success" label="Alive" />|

  defp heartbeat_status_badge(%{status: :missed} = assigns),
    do: ~H|<.badge variant="error" label="Missed" />|

  defp heartbeat_status_badge(%{status: :pending} = assigns),
    do: ~H|<.badge variant="neutral" label="Pending" />|

  defp heartbeat_status_badge(%{status: :paused} = assigns),
    do: ~H|<.badge variant="neutral" label="Paused" />|

  defp format_latency(%Check{latency_ms: ms}) when is_integer(ms), do: "#{ms} ms"
  defp format_latency(_), do: "—"

  defp format_time(%DateTime{} = dt), do: relative_time(dt)
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
