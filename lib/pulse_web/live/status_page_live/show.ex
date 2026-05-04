defmodule PulseWeb.StatusPageLive.Show do
  use PulseWeb, :live_view

  alias Pulse.{Heartbeats, Monitoring, StatusPages}

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
     |> assign_summary(page)}
  end

  @impl true
  def handle_info(
        {:status_page_updated, %{id: id} = updated},
        %{assigns: %{status_page: %{id: id}}} = socket
      ) do
    page = StatusPages.get_status_page!(updated.id)
    {:noreply, assign_summary(socket, page)}
  end

  def handle_info(
        {:status_page_deleted, %{id: id}},
        %{assigns: %{status_page: %{id: id}}} = socket
      ) do
    {:noreply,
     socket
     |> put_flash(:info, "Status page deleted")
     |> push_navigate(to: ~p"/status-pages")}
  end

  def handle_info(_msg, socket) do
    {:noreply, assign_summary(socket, socket.assigns.status_page)}
  end

  @impl true
  def handle_event("delete", _, socket) do
    {:ok, _} = StatusPages.delete_status_page(socket.assigns.status_page)

    {:noreply,
     socket
     |> put_flash(:info, "Status page deleted")
     |> push_navigate(to: ~p"/status-pages")}
  end

  defp assign_summary(socket, page) do
    socket
    |> assign(:status_page, page)
    |> assign(:summary, StatusPages.summarize(page))
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
          <.button
            variant="secondary"
            href={~p"/status/#{@status_page.slug}"}
            target="_blank"
            icon="hero-arrow-top-right-on-square"
            label="Open public page"
          />
          <.button
            variant="secondary"
            navigate={~p"/status-pages/#{@status_page.id}/edit"}
            icon="hero-pencil-square-mini"
            label="Edit"
          />
          <.button
            variant="tertiary"
            icon="hero-trash-mini"
            phx-click="delete"
            data-confirm={"Delete status page #{@status_page.name}?"}
          />
        </:actions>
      </.header>

      <div class="rounded-xl border border-border-1 bg-surface-default p-6 space-y-6">
        <div class="text-caption-1 text-text-muted">
          Public URL: <span class="text-text-default">/status/{@status_page.slug}</span>
          · {if @status_page.enabled, do: "Enabled", else: "Disabled (returns 404)"}
        </div>

        <.status_summary summary={@summary} />
      </div>
    </Layouts.app>
    """
  end
end
