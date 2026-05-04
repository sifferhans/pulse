defmodule Pulse.Notifications.ChannelTest do
  use Pulse.DataCase, async: false

  alias Pulse.Notifications.Channel

  describe "changeset/2 — slack/discord" do
    test "valid with webhook_url; config is built from the virtual field" do
      attrs = %{
        "name" => "ops",
        "kind" => "slack",
        "webhook_url" => "https://hooks.slack.com/services/T0/B0/abc"
      }

      changeset = Channel.changeset(%Channel{}, attrs)
      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :config) == %{
               "webhook_url" => "https://hooks.slack.com/services/T0/B0/abc"
             }
    end

    test "rejects a missing webhook_url for slack" do
      changeset = Channel.changeset(%Channel{}, %{"name" => "ops", "kind" => "slack"})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).webhook_url
    end

    test "rejects a missing webhook_url for discord" do
      changeset = Channel.changeset(%Channel{}, %{"name" => "ops", "kind" => "discord"})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).webhook_url
    end
  end

  describe "changeset/2 — telegram" do
    test "valid with bot_token + chat_id; config is built from virtual fields" do
      attrs = %{
        "name" => "ops",
        "kind" => "telegram",
        "bot_token" => "123:abc",
        "chat_id" => "-1001234"
      }

      changeset = Channel.changeset(%Channel{}, attrs)
      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :config) == %{
               "bot_token" => "123:abc",
               "chat_id" => "-1001234"
             }
    end

    test "rejects when bot_token or chat_id is missing" do
      changeset =
        Channel.changeset(%Channel{}, %{
          "name" => "ops",
          "kind" => "telegram",
          "bot_token" => "123:abc"
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).chat_id
    end
  end

  describe "changeset/2 — generic" do
    test "rejects an unknown kind" do
      changeset =
        Channel.changeset(%Channel{}, %{"name" => "ops", "kind" => "smoke-signal"})

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).kind
    end

    test "requires name and kind" do
      changeset = Channel.changeset(%Channel{}, %{})
      assert "can't be blank" in errors_on(changeset).name
      assert "can't be blank" in errors_on(changeset).kind
    end
  end

  describe "with_form_fields/1" do
    test "projects saved config back onto virtual fields" do
      channel = %Channel{
        kind: "telegram",
        config: %{"bot_token" => "T", "chat_id" => "C"}
      }

      hydrated = Channel.with_form_fields(channel)
      assert hydrated.bot_token == "T"
      assert hydrated.chat_id == "C"
    end
  end
end
