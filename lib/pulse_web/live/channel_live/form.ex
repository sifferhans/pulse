defmodule PulseWeb.ChannelLive.Form do
  use PulseWeb, :live_view

  alias Pulse.Notifications
  alias Pulse.Notifications.Channel

  @impl true
  def mount(params, _session, socket) do
    {channel, action, page_title} =
      case params do
        %{"id" => id} ->
          {Notifications.get_channel!(id) |> Channel.with_form_fields(), :edit,
           "Edit channel"}

        _ ->
          {%Channel{kind: "slack"}, :new, "New channel"}
      end

    changeset = Notifications.change_channel(channel)

    {:ok,
     socket
     |> assign(:page_title, page_title)
     |> assign(:action, action)
     |> assign(:channel, channel)
     |> assign(:kind_options, Enum.map(Channel.kinds(), &{String.capitalize(&1), &1}))
     |> assign(:form, to_form(changeset))}
  end

  @impl true
  def handle_event("validate", %{"channel" => params}, socket) do
    changeset =
      socket.assigns.channel
      |> Notifications.change_channel(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"channel" => params}, socket) do
    save_channel(socket, socket.assigns.action, params)
  end

  defp save_channel(socket, :new, params) do
    case Notifications.create_channel(params) do
      {:ok, _channel} ->
        {:noreply,
         socket
         |> put_flash(:info, "Channel created")
         |> push_navigate(to: ~p"/alerting")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_channel(socket, :edit, params) do
    case Notifications.update_channel(socket.assigns.channel, params) do
      {:ok, _channel} ->
        {:noreply,
         socket
         |> put_flash(:info, "Channel updated")
         |> push_navigate(to: ~p"/alerting")}

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
          Where Pulse should send alerts when an incident opens or recovers.
        </:subtitle>
      </.header>

      <.form
        for={@form}
        id="channel-form"
        phx-change="validate"
        phx-submit="save"
        class="space-y-4 rounded-xl border border-border-1 bg-surface-default p-6"
      >
        <.input field={@form[:name]} type="text" label="Name" placeholder="Engineering Slack" />

        <.input field={@form[:kind]} type="select" label="Kind" options={@kind_options} />

        <.input
          :if={@form[:kind].value in ["slack", "discord"]}
          field={@form[:webhook_url]}
          type="url"
          label="Webhook URL"
          placeholder={
            if @form[:kind].value == "slack",
              do: "https://hooks.slack.com/services/...",
              else: "https://discord.com/api/webhooks/..."
          }
        />

        <div :if={@form[:kind].value == "telegram"} class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <.input
            field={@form[:bot_token]}
            type="text"
            label="Bot token"
            placeholder="123456:ABC-DEF..."
          />
          <.input
            field={@form[:chat_id]}
            type="text"
            label="Chat ID"
            placeholder="-1001234567890"
          />
        </div>

        <.input field={@form[:enabled]} type="switch" label="Enabled" />

        <div class="flex items-center justify-end gap-2 pt-2">
          <.button variant="secondary" navigate={~p"/alerting"} label="Cancel" />
          <.button type="submit" label="Save channel" />
        </div>
      </.form>
    </Layouts.app>
    """
  end
end
