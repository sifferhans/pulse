defmodule PulseWeb.MonitorLive.Form do
  use PulseWeb, :live_view

  alias Pulse.Monitoring
  alias Pulse.Monitoring.{Monitor, WorkerSupervisor}

  @impl true
  def mount(params, _session, socket) do
    {monitor, action, page_title} =
      case params do
        %{"id" => id} ->
          monitor = Monitoring.get_monitor!(id)
          {monitor, :edit, "Edit monitor"}

        _ ->
          {%Monitor{}, :new, "New monitor"}
      end

    monitor = %{monitor | headers_text: Monitor.format_headers(monitor.headers)}
    changeset = Monitoring.change_monitor(monitor)

    {:ok,
     socket
     |> assign(:page_title, page_title)
     |> assign(:action, action)
     |> assign(:monitor, monitor)
     |> assign(:method_options, Enum.map(Monitor.methods(), &{&1, &1}))
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"monitor" => params}, socket) do
    changeset =
      socket.assigns.monitor
      |> Monitoring.change_monitor(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"monitor" => params}, socket) do
    save_monitor(socket, socket.assigns.action, params)
  end

  defp save_monitor(socket, :new, params) do
    case Monitoring.create_monitor(params) do
      {:ok, monitor} ->
        if monitor.enabled, do: WorkerSupervisor.ensure_started(monitor)

        {:noreply,
         socket
         |> put_flash(:info, "Monitor created")
         |> push_navigate(to: ~p"/monitors/#{monitor.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_monitor(socket, :edit, params) do
    case Monitoring.update_monitor(socket.assigns.monitor, params) do
      {:ok, _monitor} ->
        WorkerSupervisor.sync_all()

        {:noreply,
         socket
         |> put_flash(:info, "Monitor updated")
         |> push_navigate(to: ~p"/monitors/#{socket.assigns.monitor.id}")}

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
          Configure how often to probe an endpoint and what counts as healthy.
        </:subtitle>
      </.header>

      <.form
        for={@form}
        id="monitor-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4 rounded-xl border border-border-1 bg-surface-default p-6"
      >
        <.input field={@form[:name]} type="text" label="Name" placeholder="API · production" />
        <.input field={@form[:url]} type="url" label="URL" placeholder="https://example.com/health" />

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
          <.input
            field={@form[:method]}
            type="select"
            label="Method"
            options={@method_options}
          />
          <.input
            field={@form[:interval_seconds]}
            type="number"
            label="Interval (seconds)"
            min="10"
          />
          <.input
            field={@form[:timeout_ms]}
            type="number"
            label="Timeout (ms)"
            min="100"
          />
        </div>

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <.input
            field={@form[:expected_status]}
            type="number"
            label="Expected status code"
            min="100"
            max="599"
          />
          <.input
            field={@form[:expected_body_contains]}
            type="text"
            label="Body must contain (optional)"
            placeholder="ok"
          />
        </div>

        <.input
          field={@form[:headers_text]}
          type="textarea"
          label="Request headers (optional)"
          placeholder="Authorization: Bearer xxx\nContent-Type: application/json"
          rows="3"
        />

        <.input
          :if={@form[:method].value == "POST"}
          field={@form[:body]}
          type="textarea"
          label="Request body"
          placeholder={~s({"ping": true})}
          rows="4"
        />

        <.input field={@form[:enabled]} type="switch" label="Enabled" />

        <div class="flex items-center justify-end gap-2 pt-2">
          <.button variant="secondary" navigate={~p"/"} label="Cancel" />
          <.button type="submit" label="Save monitor" />
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
