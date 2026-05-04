defmodule PulseWeb.StatusPageLive.Show do
  use PulseWeb, :live_view

  alias Pulse.{Heartbeats, Monitoring, Status, StatusPages}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    page = StatusPages.get_status_page!(id)

    if connected?(socket) do
      Monitoring.subscribe_to_monitors()
      Heartbeats.subscribe_to_heartbeats()
      StatusPages.subscribe_to_status_pages()
    end

    {:ok,
     socket
     |> assign(:page_title, page.name)
     |> assign(:status_page, page)
     |> assign_rows(page)}
  end

  @impl true
  def handle_info({:status_page_updated, %{id: id} = updated}, %{assigns: %{status_page: %{id: id}}} = socket) do
    page = StatusPages.get_status_page!(updated.id)
    {:noreply, socket |> assign(:status_page, page) |> assign_rows(page)}
  end

  def handle_info({:status_page_deleted, %{id: id}}, %{assigns: %{status_page: %{id: id}}} = socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Status page deleted")
     |> push_navigate(to: ~p"/status-pages")}
  end

  def handle_info(_msg, socket) do
    {:noreply, assign_rows(socket, socket.assigns.status_page)}
  end

  @impl true
  def handle_event("delete", _, socket) do
    {:ok, _} = StatusPages.delete_status_page(socket.assigns.status_page)

    {:noreply,
     socket
     |> put_flash(:info, "Status page deleted")
     |> push_navigate(to: ~p"/status-pages")}
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

    socket
    |> assign(:monitor_rows, monitor_rows)
    |> assign(:heartbeat_rows, heartbeat_rows)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@status_page.name}
        <:subtitle>
          Preview of the public status page. Visitors see the same content without admin chrome.
        </:subtitle>
        <:actions>
          <.button variant="secondary" href={~p"/status/#{@status_page.slug}"} target="_blank" icon="hero-arrow-top-right-on-square" label="Open public page" />
          <.button variant="secondary" navigate={~p"/status-pages/#{@status_page.id}/edit"} icon="hero-pencil-square-mini" label="Edit" />
          <.button
            variant="tertiary"
            icon="hero-trash-mini"
            phx-click="delete"
            data-confirm={"Delete status page #{@status_page.name}?"}
          />
        </:actions>
      </.header>

      <div class="rounded-xl border border-border-1 bg-surface-default p-6">
        <div class="text-caption-1 text-text-muted">
          Public URL: <span class="text-text-default">/status/{@status_page.slug}</span> · {if @status_page.enabled, do: "Enabled", else: "Disabled (returns 404)"}
        </div>

        <div class="mt-6">
          <.status_listing monitor_rows={@monitor_rows} heartbeat_rows={@heartbeat_rows} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :monitor_rows, :list, required: true
  attr :heartbeat_rows, :list, required: true

  def status_listing(assigns) do
    ~H"""
    <div class="space-y-6">
      <p
        :if={@monitor_rows == [] and @heartbeat_rows == []}
        class="text-body-3 text-text-muted"
      >
        No monitors or heartbeats selected for this page.
      </p>

      <section :if={@monitor_rows != []} class="space-y-2">
        <h3 class="text-title-3 font-semibold text-text-default">Monitors</h3>
        <ul class="divide-y divide-border-1 rounded-lg border border-border-1 bg-surface-default">
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
        <h3 class="text-title-3 font-semibold text-text-default">Heartbeats</h3>
        <ul class="divide-y divide-border-1 rounded-lg border border-border-1 bg-surface-default">
          <li
            :for={%{heartbeat: h, status: status} <- @heartbeat_rows}
            class="flex items-center justify-between px-4 py-3"
          >
            <span class="text-body-3 text-text-default font-medium">{h.name}</span>
            <.status_badge status={status} />
          </li>
        </ul>
      </section>
    </div>
    """
  end
end
