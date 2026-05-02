defmodule Pulse.Notifications.Discord do
  @moduledoc "Posts a plain-text message to a Discord webhook."

  def send(%{"webhook_url" => url}, message) when is_binary(url) do
    Req.post(url,
      json: %{content: message},
      finch: Pulse.Monitoring.Finch,
      receive_timeout: 5_000,
      retry: false
    )
  end

  def send(_, _), do: {:error, :invalid_config}
end
