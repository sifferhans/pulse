defmodule Pulse.HeartbeatsTest do
  use Pulse.DataCase, async: false

  import Pulse.Fixtures

  alias Pulse.Heartbeats
  alias Pulse.Heartbeats.{Heartbeat, Incident}
  alias Pulse.Repo

  describe "create_heartbeat/1" do
    test "auto-generates a slug when one isn't provided" do
      assert {:ok, %Heartbeat{} = heartbeat} = Heartbeats.create_heartbeat(heartbeat_attrs())
      assert is_binary(heartbeat.slug)
      assert byte_size(heartbeat.slug) > 0
    end

    test "broadcasts :heartbeat_created" do
      Heartbeats.subscribe_to_heartbeats()
      assert {:ok, heartbeat} = Heartbeats.create_heartbeat(heartbeat_attrs())
      assert_receive {:heartbeat_created, ^heartbeat}
    end
  end

  describe "record_ping/2" do
    test "inserts a ping and updates last_pinged_at" do
      heartbeat = heartbeat_fixture()
      Heartbeats.subscribe_to_heartbeat(heartbeat)

      assert {:ok, ping} = Heartbeats.record_ping(heartbeat, %{source_ip: "127.0.0.1"})
      assert ping.heartbeat_id == heartbeat.id
      assert ping.source_ip == "127.0.0.1"

      reloaded = Repo.get!(Heartbeat, heartbeat.id)
      assert reloaded.last_pinged_at != nil
      assert DateTime.compare(reloaded.last_pinged_at, ping.pinged_at) == :eq

      assert_receive {:ping_recorded, ^ping}
    end

    test "closes any open incident for this heartbeat" do
      heartbeat = heartbeat_fixture()
      open = heartbeat_incident_fixture(heartbeat)
      Heartbeats.subscribe_to_heartbeat(heartbeat)

      assert {:ok, _ping} = Heartbeats.record_ping(heartbeat)
      assert_receive {:incident_closed, %Incident{id: id}} when id == open.id

      refute Heartbeats.open_incident_for(heartbeat)
    end

    test "leaves no open incident when there was none to begin with" do
      heartbeat = heartbeat_fixture()
      assert {:ok, _ping} = Heartbeats.record_ping(heartbeat)
      refute Heartbeats.open_incident_for(heartbeat)
    end
  end

  describe "deadline/1" do
    test "uses last_pinged_at when present" do
      pinged_at = ~U[2026-01-01 00:00:00.000000Z]

      heartbeat = %Heartbeat{
        last_pinged_at: pinged_at,
        inserted_at: ~U[2025-01-01 00:00:00Z],
        expected_interval_seconds: 300,
        grace_seconds: 60
      }

      assert Heartbeats.deadline(heartbeat) == DateTime.add(pinged_at, 360, :second)
    end

    test "falls back to inserted_at when no ping has arrived" do
      inserted_at = ~U[2026-01-01 00:00:00Z]

      heartbeat = %Heartbeat{
        last_pinged_at: nil,
        inserted_at: inserted_at,
        expected_interval_seconds: 300,
        grace_seconds: 60
      }

      assert Heartbeats.deadline(heartbeat) == DateTime.add(inserted_at, 360, :second)
    end
  end

  describe "list_overdue/1" do
    test "includes enabled heartbeats whose deadline has passed" do
      heartbeat = heartbeat_fixture(%{"expected_interval_seconds" => 30})
      now = DateTime.add(heartbeat.inserted_at, 3_600, :second)

      assert [%Heartbeat{id: id}] = Heartbeats.list_overdue(now)
      assert id == heartbeat.id
    end

    test "excludes heartbeats with an open incident (already detected)" do
      heartbeat = heartbeat_fixture(%{"expected_interval_seconds" => 30})
      heartbeat_incident_fixture(heartbeat)
      now = DateTime.add(heartbeat.inserted_at, 3_600, :second)

      assert Heartbeats.list_overdue(now) == []
    end

    test "excludes disabled heartbeats" do
      heartbeat = heartbeat_fixture(%{"expected_interval_seconds" => 30})

      heartbeat
      |> Ecto.Changeset.change(%{enabled: false})
      |> Repo.update!()

      now = DateTime.add(heartbeat.inserted_at, 3_600, :second)
      assert Heartbeats.list_overdue(now) == []
    end

    test "excludes heartbeats whose deadline is still in the future" do
      heartbeat = heartbeat_fixture(%{"expected_interval_seconds" => 3_600})
      now = DateTime.add(heartbeat.inserted_at, 60, :second)
      assert Heartbeats.list_overdue(now) == []
    end
  end

  describe "incidents" do
    test "open_incident/2 broadcasts and shows up in list_open_incidents" do
      heartbeat = heartbeat_fixture()
      Heartbeats.subscribe_to_heartbeat(heartbeat)

      assert {:ok, incident} = Heartbeats.open_incident(heartbeat, DateTime.utc_now())
      assert Incident.open?(incident)
      assert_receive {:incident_opened, ^incident}

      ids = Heartbeats.list_open_incidents() |> Enum.map(& &1.id)
      assert incident.id in ids
    end
  end
end
