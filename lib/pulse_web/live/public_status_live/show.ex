defmodule PulseWeb.PublicStatusLive.Show do
  use PulseWeb, :live_view

  alias Pulse.{Heartbeats, Monitoring, Status, StatusPages}
  alias Pulse.StatusPages.StatusPage

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case StatusPages.get_enabled_status_page_by_slug(slug) do
      nil ->
        raise Ecto.NoResultsError, queryable: StatusPage

      page ->
        if connected?(socket) do
          Monitoring.subscribe_to_monitors()
          Heartbeats.subscribe_to_heartbeats()
        end

        {:ok,
         socket
         |> assign(:page_title, page.name)
         |> assign(:status_page, page)
         |> assign_rows(page),
         layout: false}
    end
  end

  @impl true
  def handle_info(_msg, socket) do
    page = StatusPages.get_enabled_status_page_by_slug(socket.assigns.status_page.slug)

    case page do
      nil -> {:noreply, push_navigate(socket, to: ~p"/")}
      page -> {:noreply, socket |> assign(:status_page, page) |> assign_rows(page)}
    end
  end

  defp assign_rows(socket, page) do
    latest_checks = Monitoring.latest_checks_by_monitor()

    monitor_rows =
      Enum.map(page.monitors, fn m ->
        %{monitor: m, status: Status.monitor_status(m, Map.get(latest_checks, m.id))}
      end)

    open_heartbeat_incidents =
      Heartbeats.list_open_incidents()
      |> Map.new(&{&1.heartbeat_id, &1})

    heartbeat_rows =
      Enum.map(page.heartbeats, fn h ->
        %{
          heartbeat: h,
          status: Status.heartbeat_status(h, Map.get(open_heartbeat_incidents, h.id))
        }
      end)

    overall =
      cond do
        Enum.any?(monitor_rows, &(&1.status == :down)) -> :down
        Enum.any?(heartbeat_rows, &(&1.status == :missed)) -> :down
        monitor_rows == [] and heartbeat_rows == [] -> :pending
        true -> :up
      end

    socket
    |> assign(:monitor_rows, monitor_rows)
    |> assign(:heartbeat_rows, heartbeat_rows)
    |> assign(:overall, overall)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.public flash={@flash}>
      <header class="space-y-2 text-center">
        <h1 class="text-title-1 font-semibold text-text-default">{@status_page.name}</h1>
        <.overall_banner status={@overall} />
      </header>

      <div :if={@monitor_rows == [] and @heartbeat_rows == []} class="text-center text-body-3 text-text-muted">
        Nothing is currently being tracked on this page.
      </div>

      <section :if={@monitor_rows != []} class="space-y-2">
        <h2 class="text-title-3 font-semibold text-text-default">Monitors</h2>
        <ul class="divide-y divide-border-1 rounded-xl border border-border-1 bg-surface-default">
          <li
            :for={%{monitor: m, status: status} <- @monitor_rows}
            class="flex items-center justify-between px-4 py-3"
          >
            <span class="text-body-3 text-text-default font-medium">{m.name}</span>
            <.status_badge status={status} />
          </li>
        </ul>
      </section>

      <section :if={@heartbeat_rows != []} class="space-y-2">
        <h2 class="text-title-3 font-semibold text-text-default">Heartbeats</h2>
        <ul class="divide-y divide-border-1 rounded-xl border border-border-1 bg-surface-default">
          <li
            :for={%{heartbeat: h, status: status} <- @heartbeat_rows}
            class="flex items-center justify-between px-4 py-3"
          >
            <span class="text-body-3 text-text-default font-medium">{h.name}</span>
            <.status_badge status={status} />
          </li>
        </ul>
      </section>
    </Layouts.public>
    """
  end

  attr :status, :atom, required: true

  defp overall_banner(%{status: :up} = assigns),
    do: ~H|<div class="inline-flex items-center gap-2 rounded-lg bg-semantic-success/15 px-3 py-1.5 text-body-3 text-semantic-success"><.icon name="hero-check-circle-mini" class="size-4" /> All systems operational</div>|

  defp overall_banner(%{status: :down} = assigns),
    do: ~H|<div class="inline-flex items-center gap-2 rounded-lg bg-semantic-error/15 px-3 py-1.5 text-body-3 text-semantic-error"><.icon name="hero-exclamation-triangle-mini" class="size-4" /> Some systems are experiencing issues</div>|

  defp overall_banner(%{status: :pending} = assigns),
    do: ~H|<div class="inline-flex items-center gap-2 rounded-lg bg-surface-indent px-3 py-1.5 text-body-3 text-text-muted">No status data yet</div>|
end
