defmodule Pulse.Notifications.Slack do
  @moduledoc "Posts a plain-text message to a Slack incoming webhook."

  def send(%{"webhook_url" => url}, message) when is_binary(url) do
    Req.post(url,
      json: %{text: message},
      finch: Pulse.Monitoring.Finch,
      receive_timeout: 5_000,
      retry: false
    )
  end

  def send(_, _), do: {:error, :invalid_config}
end
