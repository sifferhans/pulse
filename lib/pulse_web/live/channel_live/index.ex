defmodule PulseWeb.ChannelLive.Index do
  use PulseWeb, :live_view

  alias Pulse.Notifications

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Notifications.subscribe_to_channels()

    {:ok,
     socket
     |> assign(:page_title, "Alerting")
     |> load_channels()}
  end

  @impl true
  def handle_info({event, _payload}, socket)
      when event in [:channel_created, :channel_updated, :channel_deleted] do
    {:noreply, load_channels(socket)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    channel = Notifications.get_channel!(id)
    {:ok, _} = Notifications.delete_channel(channel)

    {:noreply,
     socket
     |> put_flash(:info, "Channel #{channel.name} deleted")
     |> load_channels()}
  end

  defp load_channels(socket) do
    assign(socket, :channels, Notifications.list_channels())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Alerting
        <:subtitle>
          Configure how Pulse notifies you when incidents open or recover.
        </:subtitle>
      </.header>

      <section class="space-y-3">
        <div class="flex items-end justify-between gap-4">
          <div>
            <h2 class="text-title-3 font-semibold text-text-default">Notification channels</h2>
            <p class="text-caption-1 text-text-muted">
              Webhook destinations that receive incident alerts. Attach them to monitors and heartbeats from their edit pages.
            </p>
          </div>
          <.button
            :if={@channels != []}
            navigate={~p"/alerting/channels/new"}
            icon="hero-plus"
            label="New channel"
          />
        </div>

        <div :if={@channels == []} class="rounded-xl border border-border-1 bg-surface-default py-16">
          <.empty_state
            icon="hero-bell"
            title="No channels yet"
            description="Add a Slack, Discord, or Telegram destination to start receiving alerts."
          >
            <:action>
              <.button navigate={~p"/alerting/channels/new"} icon="hero-plus" label="New channel" />
            </:action>
          </.empty_state>
        </div>

        <.simple_table :if={@channels != []} columns={["Kind", "Name", "Status", ""]}>
          <tr
            :for={channel <- @channels}
            id={"channel-#{channel.id}"}
            class="border-t border-border-1"
          >
            <td class="px-4 py-2.5 align-middle text-body-3 text-text-muted uppercase">
              {channel.kind}
            </td>
            <td class="px-4 py-2.5 align-middle text-body-3 text-text-default font-medium">
              {channel.name}
            </td>
            <td class="px-4 py-2.5 align-middle">
              <.badge
                variant={if channel.enabled, do: "success", else: "neutral"}
                label={if channel.enabled, do: "Enabled", else: "Disabled"}
              />
            </td>
            <td class="px-4 py-2.5 align-middle">
              <div class="flex items-center justify-end gap-2">
                <.button
                  variant="tertiary"
                  size="small"
                  icon="hero-pencil-square-mini"
                  navigate={~p"/alerting/channels/#{channel.id}/edit"}
                />
                <.button
                  variant="tertiary"
                  size="small"
                  icon="hero-trash-mini"
                  phx-click={JS.push("delete", value: %{id: channel.id})}
                  data-confirm={"Delete channel #{channel.name}?"}
                />
              </div>
            </td>
          </tr>
        </.simple_table>
      </section>
    </Layouts.app>
    """
  end
end
