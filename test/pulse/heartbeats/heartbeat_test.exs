defmodule Pulse.Heartbeats.HeartbeatTest do
  use Pulse.DataCase, async: true

  alias Pulse.Heartbeats.Heartbeat

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{"name" => "Nightly job", "expected_interval_seconds" => 300, "grace_seconds" => 60},
      overrides
    )
  end

  describe "changeset/2" do
    test "valid with required fields" do
      assert Heartbeat.changeset(%Heartbeat{}, valid_attrs()).valid?
    end

    test "requires name" do
      changeset = Heartbeat.changeset(%Heartbeat{}, %{})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "auto-generates a slug when none is set" do
      changeset = Heartbeat.changeset(%Heartbeat{}, valid_attrs())
      slug = Ecto.Changeset.get_change(changeset, :slug)
      assert is_binary(slug)
      assert byte_size(slug) >= 12
    end

    test "preserves an existing slug" do
      changeset = Heartbeat.changeset(%Heartbeat{slug: "preset"}, valid_attrs())
      refute Ecto.Changeset.get_change(changeset, :slug)
    end

    test "rejects an interval under 30s" do
      changeset =
        Heartbeat.changeset(%Heartbeat{}, valid_attrs(%{"expected_interval_seconds" => 10}))

      assert errors_on(changeset).expected_interval_seconds != []
    end

    test "rejects a negative grace value" do
      changeset = Heartbeat.changeset(%Heartbeat{}, valid_attrs(%{"grace_seconds" => -1}))
      assert errors_on(changeset).grace_seconds != []
    end
  end
end
