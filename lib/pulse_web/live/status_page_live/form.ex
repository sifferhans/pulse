defmodule PulseWeb.StatusPageLive.Form do
  use PulseWeb, :live_view

  alias Pulse.{Heartbeats, Monitoring, StatusPages}
  alias Pulse.StatusPages.StatusPage

  @impl true
  def mount(params, _session, socket) do
    {page, action, page_title} =
      case params do
        %{"id" => id} ->
          page = StatusPages.get_status_page!(id)
          {page, :edit, "Edit status page"}

        _ ->
          {%StatusPage{monitors: [], heartbeats: []}, :new, "New status page"}
      end

    changeset = StatusPages.change_status_page(page)

    {:ok,
     socket
     |> assign(:page_title, page_title)
     |> assign(:action, action)
     |> assign(:status_page, page)
     |> assign(:monitors, Monitoring.list_monitors())
     |> assign(:heartbeats, Heartbeats.list_heartbeats())
     |> assign(:selected_monitor_ids, Enum.map(page.monitors, & &1.id))
     |> assign(:selected_heartbeat_ids, Enum.map(page.heartbeats, & &1.id))
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"status_page" => params}, socket) do
    changeset =
      socket.assigns.status_page
      |> StatusPages.change_status_page(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:selected_monitor_ids, parse_ids(params, "monitor_ids"))
     |> assign(:selected_heartbeat_ids, parse_ids(params, "heartbeat_ids"))}
  end

  def handle_event("save", %{"status_page" => params}, socket) do
    save(socket, socket.assigns.action, params)
  end

  defp parse_ids(params, key) do
    case Map.get(params, key) do
      nil ->
        []

      list when is_list(list) ->
        list |> Enum.reject(&(&1 == "")) |> Enum.map(&String.to_integer/1)

      _ ->
        []
    end
  end

  defp save(socket, :new, params) do
    case StatusPages.create_status_page(params) do
      {:ok, page} ->
        {:noreply,
         socket
         |> put_flash(:info, "Status page created")
         |> push_navigate(to: ~p"/status-pages/#{page.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save(socket, :edit, params) do
    case StatusPages.update_status_page(socket.assigns.status_page, params) do
      {:ok, _page} ->
        {:noreply,
         socket
         |> put_flash(:info, "Status page updated")
         |> push_navigate(to: ~p"/status-pages/#{socket.assigns.status_page.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@page_title}
        <:subtitle>
          Curate a public status view by selecting which monitors and heartbeats to display.
        </:subtitle>
      </.header>

      <.form
        for={@form}
        id="status-page-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-6 rounded-xl border border-border-1 bg-surface-default p-6"
      >
        <.input field={@form[:name]} type="text" label="Name" placeholder="Public services" />

        <.entity_picker
          title="Monitors"
          empty_label="No monitors to display."
          entities={@monitors}
          selected_ids={@selected_monitor_ids}
          form_name={@form.name}
          field_name="monitor_ids"
        />

        <.entity_picker
          title="Heartbeats"
          empty_label="No heartbeats to display."
          entities={@heartbeats}
          selected_ids={@selected_heartbeat_ids}
          form_name={@form.name}
          field_name="heartbeat_ids"
        />

        <.input field={@form[:enabled]} type="switch" label="Enabled" />

        <div class="flex items-center justify-end gap-2 pt-2">
          <.button variant="secondary" navigate={~p"/status-pages"} label="Cancel" />
          <.button type="submit" label="Save status page" />
        </div>
      </.form>
    </Layouts.app>
    """
  end

  attr :title, :string, required: true
  attr :empty_label, :string, required: true
  attr :entities, :list, required: true
  attr :selected_ids, :list, required: true
  attr :form_name, :string, required: true
  attr :field_name, :string, required: true

  defp entity_picker(assigns) do
    ~H"""
    <div>
      <div class="text-body-3 font-medium text-text-default">{@title}</div>
      <p :if={@entities == []} class="mt-0.5 text-caption-1 text-text-muted">
        {@empty_label}
      </p>
      <div :if={@entities != []} class="mt-3 grid grid-cols-1 gap-2 sm:grid-cols-2">
        <input type="hidden" name={"#{@form_name}[#{@field_name}][]"} value="" />
        <label
          :for={entity <- @entities}
          class="group flex cursor-pointer items-center gap-3 rounded-lg border border-border-1 bg-surface-default px-3 py-2.5 transition-colors hover:bg-surface-indent has-checked:border-primary-contrast has-checked:bg-primary-contrast/5"
        >
          <input
            type="checkbox"
            name={"#{@form_name}[#{@field_name}][]"}
            value={entity.id}
            checked={entity.id in @selected_ids}
            class="size-4 shrink-0 rounded border-border-1 accent-primary-contrast"
          />
          <div class="min-w-0 flex-1">
            <span class="truncate text-body-3 font-medium text-text-default">{entity.name}</span>
          </div>
          <.badge :if={!entity.enabled} variant="neutral" class="shrink-0">disabled</.badge>
        </label>
      </div>
    </div>
    """
  end
end
