defmodule PulseWeb.Features.ChannelTest do
  use PulseWeb.ConnCase, async: false

  setup %{conn: conn} do
    {:ok, conn: log_in_admin(conn)}
  end

  test "creating a Slack channel returns to the alerting list", %{conn: conn} do
    conn
    |> visit(~p"/alerting/channels/new")
    |> fill_in("Name", with: "Engineering")
    |> fill_in("Webhook URL", with: "https://hooks.slack.com/services/T0/B0/secret")
    |> click_button("Save channel")
    |> assert_path(~p"/alerting")
    |> assert_has("*", text: "Engineering")
  end

  test "switching kind to telegram surfaces the bot-token + chat-id fields", %{conn: conn} do
    conn
    |> visit(~p"/alerting/channels/new")
    |> select("Kind", option: "Telegram")
    |> assert_has("label", text: "Bot token")
    |> assert_has("label", text: "Chat ID")
  end
end
