defmodule PulseWeb.StatusPageLive.Index do
  use PulseWeb, :live_view

  alias Pulse.StatusPages

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: StatusPages.subscribe_to_status_pages()

    {:ok,
     socket
     |> assign(:page_title, "Status pages")
     |> load_pages()}
  end

  @impl true
  def handle_info({event, _payload}, socket)
      when event in [:status_page_created, :status_page_updated, :status_page_deleted] do
    {:noreply, load_pages(socket)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    page = StatusPages.get_status_page!(id)
    {:ok, _} = StatusPages.delete_status_page(page)

    {:noreply,
     socket
     |> put_flash(:info, "Status page #{page.name} deleted")
     |> load_pages()}
  end

  defp load_pages(socket) do
    assign(socket, :pages, StatusPages.list_status_pages())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Status pages
        <:subtitle>
          Public, slug-addressable views that show the current status of selected monitors and heartbeats.
        </:subtitle>
        <:actions>
          <.button :if={@pages != []} navigate={~p"/status-pages/new"} icon="hero-plus" label="New status page" />
        </:actions>
      </.header>

      <div :if={@pages == []} class="rounded-xl border border-border-1 bg-surface-default py-16">
        <.empty_state
          icon="hero-globe-alt"
          title="No status pages yet"
          description="Create one to publish a curated current-status view at a stable URL."
        >
          <:action>
            <.button navigate={~p"/status-pages/new"} icon="hero-plus" label="New status page" />
          </:action>
        </.empty_state>
      </div>

      <.simple_table :if={@pages != []} columns={["Name", "Public URL", "Items", "Status", ""]}>
        <tr
          :for={page <- @pages}
          id={"status-page-#{page.id}"}
          class="border-t border-border-1"
        >
          <td class="px-4 py-2.5 align-middle text-body-3 text-text-default font-medium">
            <.link navigate={~p"/status-pages/#{page.id}"} class="hover:underline">
              {page.name}
            </.link>
          </td>
          <td class="px-4 py-2.5 align-middle text-body-3 text-text-muted">
            <.link href={~p"/status/#{page.slug}"} target="_blank" class="hover:underline">
              /status/{page.slug}
            </.link>
          </td>
          <td class="px-4 py-2.5 align-middle text-body-3 text-text-muted">
            {length(page.monitors)} monitor{plural(page.monitors)} · {length(page.heartbeats)} heartbeat{plural(page.heartbeats)}
          </td>
          <td class="px-4 py-2.5 align-middle">
            <.badge
              variant={if page.enabled, do: "success", else: "neutral"}
              label={if page.enabled, do: "Enabled", else: "Disabled"}
            />
          </td>
          <td class="px-4 py-2.5 align-middle">
            <div class="flex items-center justify-end gap-2">
              <.button
                variant="tertiary"
                size="small"
                icon="hero-pencil-square-mini"
                navigate={~p"/status-pages/#{page.id}/edit"}
              />
              <.button
                variant="tertiary"
                size="small"
                icon="hero-trash-mini"
                phx-click={JS.push("delete", value: %{id: page.id})}
                data-confirm={"Delete status page #{page.name}?"}
              />
            </div>
          </td>
        </tr>
      </.simple_table>
    </Layouts.app>
    """
  end

  defp plural([_]), do: ""
  defp plural(_), do: "s"
end
