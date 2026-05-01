defmodule PulseWeb.MonitorLive.Show do
  use PulseWeb, :live_view

  alias Pulse.Monitoring
  alias Pulse.Monitoring.{Check, Worker, WorkerSupervisor}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    monitor = Monitoring.get_monitor!(id)

    if connected?(socket), do: Monitoring.subscribe_to_monitor(monitor)

    {:ok,
     socket
     |> assign(:page_title, monitor.name)
     |> assign(:monitor, monitor)
     |> load_check_data()}
  end

  @impl true
  def handle_info({:monitor_updated, monitor}, socket) do
    {:noreply, socket |> assign(:monitor, monitor) |> load_check_data()}
  end

  def handle_info({:monitor_deleted, _monitor}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Monitor deleted")
     |> push_navigate(to: ~p"/monitors")}
  end

  def handle_info({event, _payload}, socket)
      when event in [:check_recorded, :incident_opened, :incident_closed] do
    {:noreply, load_check_data(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("run_now", _params, socket) do
    case Worker.run_now(socket.assigns.monitor.id) do
      :ok ->
        {:noreply, put_flash(socket, :info, "Probe queued")}

      {:error, :not_running} ->
        :ok = WorkerSupervisor.ensure_started(socket.assigns.monitor)
        {:noreply, put_flash(socket, :info, "Worker started")}
    end
  end

  def handle_event("delete", _params, socket) do
    {:ok, _} = Monitoring.delete_monitor(socket.assigns.monitor)
    WorkerSupervisor.stop(socket.assigns.monitor.id)

    {:noreply,
     socket
     |> put_flash(:info, "Monitor deleted")
     |> push_navigate(to: ~p"/monitors")}
  end

  defp load_check_data(socket) do
    monitor = socket.assigns.monitor
    checks = Monitoring.list_recent_checks(monitor, 50)
    incidents = Monitoring.list_recent_incidents(monitor, 10)
    open_incident = Monitoring.open_incident_for(monitor)
    latest = List.first(checks)

    socket
    |> assign(:checks, checks)
    |> assign(:incidents, incidents)
    |> assign(:open_incident, open_incident)
    |> assign(:latest_check, latest)
    |> assign(:summary, summarize(checks))
  end

  defp summarize([]),
    do: %{count: 0, uptime: nil, avg_latency: nil, p95_latency: nil}

  defp summarize(checks) do
    count = length(checks)
    up = Enum.count(checks, &(&1.status == "up"))
    latencies = checks |> Enum.map(& &1.latency_ms) |> Enum.reject(&is_nil/1) |> Enum.sort()

    %{
      count: count,
      uptime: percentage(up, count),
      avg_latency: avg(latencies),
      p95_latency: percentile(latencies, 0.95)
    }
  end

  defp percentage(_, 0), do: nil
  defp percentage(n, total), do: Float.round(n * 100 / total, 1)

  defp avg([]), do: nil
  defp avg(values), do: round(Enum.sum(values) / length(values))

  defp percentile([], _), do: nil

  defp percentile(values, p) when is_list(values) do
    idx = max(round(length(values) * p) - 1, 0)
    Enum.at(values, idx)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@monitor.name}
        <:subtitle>
          {@monitor.method} {@monitor.url} · every {humanize_seconds(@monitor.interval_seconds)}
        </:subtitle>
        <:actions>
          <.button
            variant="tertiary"
            icon="hero-arrow-path"
            label="Run now"
            phx-click="run_now"
          />
          <.button
            variant="secondary"
            icon="hero-pencil-square-mini"
            label="Edit"
            navigate={~p"/monitors/#{@monitor.id}/edit"}
          />
          <.button
            variant="tertiary"
            icon="hero-trash-mini"
            phx-click="delete"
            data-confirm={"Delete monitor #{@monitor.name}?"}
          />
        </:actions>
      </.header>

      <.banner :if={@open_incident} variant="error" icon="hero-exclamation-triangle">
        <span class="font-semibold">
          Incident open since {format_iso(@open_incident.started_at)}.
        </span>
        <span :if={@open_incident.last_error} class="opacity-80">{@open_incident.last_error}</span>
      </.banner>

      <div class="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <.stat_card label="Status">
          <.live_status check={@latest_check} incident={@open_incident} enabled={@monitor.enabled} />
        </.stat_card>
        <.stat_card label="Uptime (last 50)">
          {format_uptime(@summary.uptime)}
        </.stat_card>
        <.stat_card label="Avg latency">
          {format_ms(@summary.avg_latency)}
        </.stat_card>
        <.stat_card label="p95 latency">
          {format_ms(@summary.p95_latency)}
        </.stat_card>
      </div>

      <section class="rounded-xl border border-border-1 bg-surface-default p-4">
        <h2 class="mb-3 px-2 text-title-2 font-semibold text-text-default">Recent checks</h2>
        <.latency_strip checks={@checks} />
      </section>

      <section class="rounded-xl border border-border-1 bg-surface-default">
        <div class="flex items-center justify-between border-b border-border-1 px-4 py-3">
          <h2 class="text-title-2 font-semibold text-text-default">Check history</h2>
          <span class="text-caption-1 text-text-muted">{@summary.count} entries</span>
        </div>
        <div :if={@checks == []} class="px-4 py-12 text-center text-body-2 text-text-hint">
          No checks yet — click "Run now" or wait for the next scheduled probe.
        </div>
        <ul :if={@checks != []} class="divide-y divide-border-1">
          <li :for={check <- @checks} class="flex items-center gap-3 px-4 py-2">
            <.check_dot status={check.status} />
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2 text-body-3 text-text-default">
                <span class="font-medium">{String.upcase(check.status)}</span>
                <span :if={check.status_code} class="text-text-muted">
                  HTTP {check.status_code}
                </span>
                <span class="text-text-muted">· {format_ms(check.latency_ms)}</span>
              </div>
              <div :if={check.error} class="text-caption-1 text-semantic-error truncate">
                {check.error}
              </div>
            </div>
            <span class="text-caption-1 text-text-muted">{format_iso(check.ran_at)}</span>
          </li>
        </ul>
      </section>

      <section :if={@incidents != []} class="rounded-xl border border-border-1 bg-surface-default">
        <div class="border-b border-border-1 px-4 py-3">
          <h2 class="text-title-2 font-semibold text-text-default">Incidents</h2>
        </div>
        <ul class="divide-y divide-border-1">
          <li :for={incident <- @incidents} class="flex items-center gap-3 px-4 py-2">
            <.icon
              name={if incident.ended_at, do: "hero-check-circle", else: "hero-exclamation-triangle"}
              class={[
                "size-5",
                if(incident.ended_at, do: "text-semantic-success", else: "text-semantic-error")
              ]}
            />
            <div class="flex-1 min-w-0">
              <div class="text-body-3 text-text-default">
                {incident_duration(incident)}
              </div>
              <div :if={incident.last_error} class="text-caption-1 text-text-muted truncate">
                {incident.last_error}
              </div>
            </div>
            <span class="text-caption-1 text-text-muted">
              {format_iso(incident.started_at)}
            </span>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp stat_card(assigns) do
    ~H"""
    <div class="rounded-xl border border-border-1 bg-surface-default p-4">
      <div class="text-caption-1 text-text-muted">{@label}</div>
      <div class="mt-1 text-title-1 font-semibold text-text-default">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  attr :check, Check, default: nil
  attr :incident, :any, default: nil
  attr :enabled, :boolean, default: true

  defp live_status(%{enabled: false} = assigns) do
    ~H"""
    <.badge variant="neutral" label="Paused" />
    """
  end

  defp live_status(%{check: nil} = assigns) do
    ~H"""
    <.badge variant="neutral" label="Pending" />
    """
  end

  defp live_status(%{check: %Check{status: "up"}, incident: nil} = assigns) do
    ~H"""
    <.badge variant="success" label="Up" />
    """
  end

  defp live_status(%{check: %Check{status: status}} = assigns)
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

  defp live_status(assigns) do
    ~H"""
    <.badge variant="warning" label="Recovering" />
    """
  end

  attr :checks, :list, required: true

  defp latency_strip(assigns) do
    ~H"""
    <div class="flex items-end gap-1 px-2 h-16">
      <div :if={@checks == []} class="text-body-3 text-text-hint">No data yet.</div>
      <div :for={check <- Enum.reverse(@checks)} class="flex-1 flex flex-col items-center group">
        <div
          class={[
            "w-full rounded-t",
            check.status == "up" && "bg-semantic-success/70",
            check.status != "up" && "bg-semantic-error/70"
          ]}
          style={"height: #{bar_height(check)}%"}
          title={"#{check.status} · #{format_ms(check.latency_ms)} · #{format_iso(check.ran_at)}"}
        />
      </div>
    </div>
    """
  end

  attr :status, :string, required: true

  defp check_dot(assigns) do
    ~H"""
    <span class={[
      "inline-block size-2.5 rounded-full shrink-0",
      @status == "up" && "bg-semantic-success",
      @status in ["down", "timeout", "error"] && "bg-semantic-error"
    ]} />
    """
  end

  defp bar_height(%Check{latency_ms: nil}), do: 100
  defp bar_height(%Check{latency_ms: ms}) when ms <= 100, do: 20
  defp bar_height(%Check{latency_ms: ms}) when ms <= 500, do: 40
  defp bar_height(%Check{latency_ms: ms}) when ms <= 1_000, do: 60
  defp bar_height(%Check{latency_ms: ms}) when ms <= 3_000, do: 80
  defp bar_height(%Check{}), do: 100

  defp format_ms(nil), do: "—"
  defp format_ms(ms), do: "#{ms} ms"

  defp format_uptime(nil), do: "—"
  defp format_uptime(value), do: "#{value}%"

  defp format_iso(%DateTime{} = dt) do
    dt
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp incident_duration(%{started_at: started, ended_at: nil}) do
    diff = DateTime.diff(DateTime.utc_now(), started, :second)
    "Ongoing · #{humanize_seconds(diff)}"
  end

  defp incident_duration(%{started_at: started, ended_at: ended}) do
    diff = DateTime.diff(ended, started, :second)
    "Resolved · #{humanize_seconds(diff)}"
  end

  defp humanize_seconds(s) when s < 60, do: "#{s}s"
  defp humanize_seconds(s) when s < 3_600, do: "#{div(s, 60)}m"
  defp humanize_seconds(s) when s < 86_400, do: "#{div(s, 3_600)}h"
  defp humanize_seconds(s), do: "#{div(s, 86_400)}d"
end
