defmodule Pulse.Notifications do
  @moduledoc """
  Notification channels and dispatching. A channel is a persisted config
  (Slack/Discord webhook, Telegram bot+chat). Monitors and heartbeats can
  subscribe to any number of channels via `many_to_many` join tables.
  """

  import Ecto.Query

  alias Pulse.Notifications.{Channel, Discord, Slack, Telegram}
  alias Pulse.Repo

  @pubsub Pulse.PubSub
  @channels_topic "notifications:channels"

  ## PubSub

  def channels_topic, do: @channels_topic

  def subscribe_to_channels do
    Phoenix.PubSub.subscribe(@pubsub, @channels_topic)
  end

  ## CRUD

  def list_channels do
    Repo.all(from c in Channel, order_by: [asc: c.name])
  end

  def list_channels_by_ids([]), do: []

  def list_channels_by_ids(ids) do
    Repo.all(from c in Channel, where: c.id in ^ids)
  end

  def get_channel!(id), do: Repo.get!(Channel, id)

  def change_channel(%Channel{} = channel, attrs \\ %{}) do
    Channel.changeset(channel, attrs)
  end

  def create_channel(attrs) do
    %Channel{}
    |> Channel.changeset(attrs)
    |> Repo.insert()
    |> tap_broadcast(:channel_created)
  end

  def update_channel(%Channel{} = channel, attrs) do
    channel
    |> Channel.changeset(attrs)
    |> Repo.update()
    |> tap_broadcast(:channel_updated)
  end

  def delete_channel(%Channel{} = channel) do
    case Repo.delete(channel) do
      {:ok, deleted} = result ->
        broadcast({:channel_deleted, deleted})
        result

      other ->
        other
    end
  end

  defp tap_broadcast({:ok, %Channel{} = channel} = result, event) do
    broadcast({event, channel})
    result
  end

  defp tap_broadcast(other, _event), do: other

  defp broadcast(message), do: Phoenix.PubSub.broadcast(@pubsub, @channels_topic, message)

  ## Dispatch

  @doc """
  Sends `message` through `channel`, dispatching to the kind-specific sender.
  Returns whatever the underlying Req call returns.
  """
  def send_message(%Channel{enabled: false}, _message), do: {:ok, :disabled}

  def send_message(%Channel{kind: kind, config: config}, message) do
    case kind do
      "slack" -> Slack.send(config, message)
      "discord" -> Discord.send(config, message)
      "telegram" -> Telegram.send(config, message)
      _ -> {:error, {:unknown_kind, kind}}
    end
  end
end
