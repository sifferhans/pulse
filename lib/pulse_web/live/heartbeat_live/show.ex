defmodule PulseWeb.HeartbeatLive.Show do
  use PulseWeb, :live_view

  alias Pulse.Heartbeats
  alias Pulse.Heartbeats.Heartbeat

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    heartbeat = Heartbeats.get_heartbeat!(id)

    if connected?(socket), do: Heartbeats.subscribe_to_heartbeat(heartbeat)

    {:ok,
     socket
     |> assign(:page_title, heartbeat.name)
     |> assign(:heartbeat, heartbeat)
     |> load_data()}
  end

  @impl true
  def handle_info({:heartbeat_updated, heartbeat}, socket) do
    {:noreply, socket |> assign(:heartbeat, heartbeat) |> load_data()}
  end

  def handle_info({:heartbeat_deleted, _}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Heartbeat deleted")
     |> push_navigate(to: ~p"/")}
  end

  def handle_info({event, _payload}, socket)
      when event in [:ping_recorded, :incident_opened, :incident_closed] do
    {:noreply, load_data(socket)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("delete", _params, socket) do
    {:ok, _} = Heartbeats.delete_heartbeat(socket.assigns.heartbeat)

    {:noreply,
     socket
     |> put_flash(:info, "Heartbeat deleted")
     |> push_navigate(to: ~p"/")}
  end

  defp load_data(socket) do
    heartbeat = Heartbeats.get_heartbeat!(socket.assigns.heartbeat.id)
    pings = Heartbeats.list_recent_pings(heartbeat, 50)
    incidents = Heartbeats.list_recent_incidents(heartbeat, 10)
    open_incident = Heartbeats.open_incident_for(heartbeat)
    now = DateTime.utc_now()

    socket
    |> assign(:heartbeat, heartbeat)
    |> assign(:pings, pings)
    |> assign(:incidents, incidents)
    |> assign(:open_incident, open_incident)
    |> assign(:now, now)
    |> assign(:status, status(heartbeat, open_incident))
    |> assign(:ping_url, url(~p"/ping/#{heartbeat.slug}"))
  end

  defp status(%Heartbeat{enabled: false}, _), do: :paused
  defp status(%Heartbeat{}, %{} = _open), do: :missed
  defp status(%Heartbeat{last_pinged_at: nil}, _), do: :pending
  defp status(%Heartbeat{}, _), do: :alive

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@heartbeat.name}
        <:subtitle>
          expected every {humanize_seconds(@heartbeat.expected_interval_seconds)} · grace {humanize_seconds(
            @heartbeat.grace_seconds
          )}
        </:subtitle>
        <:actions>
          <.button
            variant="secondary"
            icon="hero-pencil-square-mini"
            label="Edit"
            navigate={~p"/heartbeats/#{@heartbeat.id}/edit"}
          />
          <.button
            variant="tertiary"
            icon="hero-trash-mini"
            phx-click="delete"
            data-confirm={"Delete heartbeat #{@heartbeat.name}?"}
          />
        </:actions>
      </.header>

      <.banner :if={@open_incident} variant="error" icon="hero-exclamation-triangle">
        <span class="font-semibold">
          Missed since {format_iso(@open_incident.started_at)}.
        </span>
        <span class="opacity-80">
          Last ping was {format_iso(@heartbeat.last_pinged_at) || "never"}.
        </span>
      </.banner>

      <section class="rounded-xl border border-border-1 bg-surface-default p-4 space-y-3">
        <div class="flex items-center justify-between">
          <h2 class="text-title-2 font-semibold text-text-default">Ping URL</h2>
          <.status_badge status={@status} />
        </div>
        <p class="text-body-3 text-text-muted">
          Make a GET, POST, or HEAD request to this URL on every successful run of your job.
          Any other response interval will mark this heartbeat as missed.
        </p>
        <pre class="rounded-md border border-border-1 bg-surface-indent px-3 py-2 text-body-3 text-text-default overflow-x-auto"><code>{@ping_url}</code></pre>
        <details class="text-body-3 text-text-muted">
          <summary class="cursor-pointer text-text-default">curl example</summary>
          <pre class="mt-2 rounded-md border border-border-1 bg-surface-indent px-3 py-2 overflow-x-auto"><code>{"curl -fsS -m 10 --retry 3 #{@ping_url}"}</code></pre>
        </details>
      </section>

      <div class="grid grid-cols-2 gap-4 sm:grid-cols-4">
        <.stat_card label="Status">
          <.status_badge status={@status} />
        </.stat_card>
        <.stat_card label="Last ping">
          {format_relative(@heartbeat.last_pinged_at, @now)}
        </.stat_card>
        <.stat_card label="Total pings">
          {length(@pings)}
        </.stat_card>
        <.stat_card label="Open incidents">
          {if @open_incident, do: 1, else: 0}
        </.stat_card>
      </div>

      <section class="rounded-xl border border-border-1 bg-surface-default">
        <div class="flex items-center justify-between border-b border-border-1 px-4 py-3">
          <h2 class="text-title-2 font-semibold text-text-default">Recent pings</h2>
          <span class="text-caption-1 text-text-muted">{length(@pings)} entries</span>
        </div>
        <div :if={@pings == []} class="px-4 py-12 text-center text-body-2 text-text-hint">
          No pings yet. Trigger a request to the URL above to record the first one.
        </div>
        <ul :if={@pings != []} class="divide-y divide-border-1">
          <li :for={ping <- @pings} class="flex items-center gap-3 px-4 py-2">
            <span class="inline-block size-2.5 rounded-full bg-semantic-success shrink-0" />
            <div class="flex-1 min-w-0">
              <div class="text-body-3 text-text-default font-medium">
                ping received
              </div>
              <div class="text-caption-1 text-text-muted truncate">
                {ping_meta(ping)}
              </div>
            </div>
            <span class="text-caption-1 text-text-muted">{format_iso(ping.pinged_at)}</span>
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

  defp ping_meta(ping) do
    [ping.source_ip, ping.user_agent]
    |> Enum.reject(&(&1 == nil or &1 == ""))
    |> Enum.join(" · ")
    |> case do
      "" -> "—"
      str -> str
    end
  end

  defp incident_duration(incident) do
    started = incident.started_at
    ended = incident.ended_at || DateTime.utc_now()
    seconds = DateTime.diff(ended, started, :second)
    suffix = if incident.ended_at, do: "resolved", else: "ongoing"
    "#{humanize_seconds(seconds)} · #{suffix}"
  end

  defp format_iso(nil), do: nil
  defp format_iso(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S UTC")

  defp format_relative(nil, _now), do: "never"

  defp format_relative(%DateTime{} = dt, now) do
    diff = DateTime.diff(now, dt, :second)

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
