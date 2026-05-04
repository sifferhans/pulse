defmodule Pulse.MonitoringTest do
  use Pulse.DataCase, async: false

  import Pulse.Fixtures

  alias Pulse.Monitoring
  alias Pulse.Monitoring.{Incident, Monitor}

  describe "create_monitor/1" do
    test "persists with defaults and broadcasts :monitor_created" do
      Monitoring.subscribe_to_monitors()
      assert {:ok, %Monitor{} = monitor} = Monitoring.create_monitor(monitor_attrs())
      assert monitor.method == "GET"
      assert monitor.enabled == true
      assert_receive {:monitor_created, ^monitor}
    end

    test "rejects an invalid URL" do
      assert {:error, changeset} =
               Monitoring.create_monitor(monitor_attrs(%{"url" => "not-a-url"}))

      assert "must be a valid http(s) URL" in errors_on(changeset).url
    end
  end

  describe "record_check/1" do
    test "inserts a check and broadcasts on both topics" do
      monitor = monitor_fixture()
      Monitoring.subscribe_to_monitors()
      Monitoring.subscribe_to_monitor(monitor)

      assert {:ok, check} =
               Monitoring.record_check(%{
                 monitor_id: monitor.id,
                 status: "up",
                 ran_at: DateTime.utc_now(),
                 latency_ms: 42
               })

      assert check.status == "up"
      assert_receive {:check_recorded, ^check}
      assert_receive {:check_recorded, ^check}
    end

    test "rejects an unknown status" do
      monitor = monitor_fixture()

      assert {:error, changeset} =
               Monitoring.record_check(%{
                 monitor_id: monitor.id,
                 status: "weird",
                 ran_at: DateTime.utc_now()
               })

      assert "is invalid" in errors_on(changeset).status
    end
  end

  describe "incident lifecycle" do
    test "open_incident/3 creates an open incident and broadcasts" do
      monitor = monitor_fixture()
      Monitoring.subscribe_to_monitor(monitor)

      assert {:ok, %Incident{} = incident} =
               Monitoring.open_incident(monitor, DateTime.utc_now(), "503 Service Unavailable")

      assert incident.ended_at == nil
      assert incident.last_error == "503 Service Unavailable"
      assert Incident.open?(incident)
      assert Monitoring.open_incident_for(monitor).id == incident.id
      assert_receive {:incident_opened, ^incident}
    end

    test "close_incident/2 sets ended_at and broadcasts" do
      monitor = monitor_fixture()
      incident = monitor_incident_fixture(monitor)
      Monitoring.subscribe_to_monitor(monitor)

      ended_at = DateTime.utc_now()
      assert {:ok, closed} = Monitoring.close_incident(incident, ended_at)
      refute Incident.open?(closed)
      assert Monitoring.open_incident_for(monitor) == nil
      assert_receive {:incident_closed, ^closed}
    end

    test "list_open_incidents/0 returns only open incidents" do
      monitor = monitor_fixture()
      open = monitor_incident_fixture(monitor)
      _closed = monitor_incident_fixture(monitor, ended_at: DateTime.utc_now())

      ids = Monitoring.list_open_incidents() |> Enum.map(& &1.id)
      assert open.id in ids
      assert length(ids) == 1
    end
  end

  describe "delete_monitor/1" do
    test "deletes the monitor and broadcasts" do
      monitor = monitor_fixture()
      Monitoring.subscribe_to_monitors()

      assert {:ok, deleted} = Monitoring.delete_monitor(monitor)
      assert_receive {:monitor_deleted, ^deleted}
      assert Monitoring.list_monitors() == []
    end
  end

  describe "latest_check/1 and latest_checks_by_monitor/0" do
    test "returns the most-recent check per monitor" do
      monitor = monitor_fixture()
      _old = check_fixture(monitor, ran_at: ~U[2026-01-01 00:00:00.000000Z], status: "down")
      newer = check_fixture(monitor, ran_at: ~U[2026-01-02 00:00:00.000000Z], status: "up")

      assert Monitoring.latest_check(monitor).id == newer.id
      assert Monitoring.latest_checks_by_monitor()[monitor.id].id == newer.id
    end
  end
end
