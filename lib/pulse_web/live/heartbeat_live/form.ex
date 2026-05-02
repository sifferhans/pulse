defmodule PulseWeb.HeartbeatLive.Form do
  use PulseWeb, :live_view

  alias Pulse.{Heartbeats, Notifications, Repo}
  alias Pulse.Heartbeats.Heartbeat

  @impl true
  def mount(params, _session, socket) do
    {heartbeat, action, page_title} =
      case params do
        %{"id" => id} ->
          heartbeat = Heartbeats.get_heartbeat!(id) |> Repo.preload(:channels)
          {heartbeat, :edit, "Edit heartbeat"}

        _ ->
          {%Heartbeat{channels: []}, :new, "New heartbeat"}
      end

    changeset = Heartbeats.change_heartbeat(heartbeat)

    {:ok,
     socket
     |> assign(:page_title, page_title)
     |> assign(:action, action)
     |> assign(:heartbeat, heartbeat)
     |> assign(:channels, Notifications.list_channels())
     |> assign(:selected_channel_ids, Enum.map(heartbeat.channels, & &1.id))
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"heartbeat" => params}, socket) do
    changeset =
      socket.assigns.heartbeat
      |> Heartbeats.change_heartbeat(params)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> assign(:selected_channel_ids, parse_channel_ids(params))}
  end

  def handle_event("save", %{"heartbeat" => params}, socket) do
    save_heartbeat(socket, socket.assigns.action, params)
  end

  defp parse_channel_ids(params) do
    case Map.get(params, "channel_ids") do
      nil -> []
      list when is_list(list) -> Enum.map(list, &String.to_integer/1)
      _ -> []
    end
  end

  defp save_heartbeat(socket, :new, params) do
    case Heartbeats.create_heartbeat(params) do
      {:ok, heartbeat} ->
        {:noreply,
         socket
         |> put_flash(:info, "Heartbeat created")
         |> push_navigate(to: ~p"/heartbeats/#{heartbeat.id}")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_heartbeat(socket, :edit, params) do
    case Heartbeats.update_heartbeat(socket.assigns.heartbeat, params) do
      {:ok, _heartbeat} ->
        {:noreply,
         socket
         |> put_flash(:info, "Heartbeat updated")
         |> push_navigate(to: ~p"/heartbeats/#{socket.assigns.heartbeat.id}")}

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
          A heartbeat is a passive monitor — point a cron job at its URL and we'll alert if it stops.
        </:subtitle>
      </.header>

      <.form
        for={@form}
        id="heartbeat-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4 rounded-xl border border-border-1 bg-surface-default p-6"
      >
        <.input field={@form[:name]} type="text" label="Name" placeholder="Nightly backup" />

        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <.input
            field={@form[:expected_interval_seconds]}
            type="number"
            label="Expected interval (seconds)"
            min="30"
            max="86400"
          />
          <.input
            field={@form[:grace_seconds]}
            type="number"
            label="Grace period (seconds)"
            min="0"
            max="3600"
          />
        </div>

        <.channel_subscriptions
          channels={@channels}
          selected_ids={@selected_channel_ids}
          form_name={@form.name}
        />

        <.input field={@form[:enabled]} type="switch" label="Enabled" />

        <div class="flex items-center justify-end gap-2 pt-2">
          <.button variant="secondary" navigate={~p"/"} label="Cancel" />
          <.button type="submit" label="Save heartbeat" />
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
