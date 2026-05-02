defmodule Pulse.Notifications.Telegram do
  @moduledoc "Sends a plain-text message via the Telegram Bot API."

  def send(%{"bot_token" => token, "chat_id" => chat}, message)
      when is_binary(token) and is_binary(chat) do
    url = "https://api.telegram.org/bot#{token}/sendMessage"

    Req.post(url,
      json: %{chat_id: chat, text: message},
      finch: Pulse.Monitoring.Finch,
      receive_timeout: 5_000,
      retry: false
    )
  end

  def send(_, _), do: {:error, :invalid_config}
end
