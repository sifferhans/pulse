defmodule Pulse.StatusTest do
  use ExUnit.Case, async: true

  alias Pulse.Heartbeats.Heartbeat
  alias Pulse.Monitoring.Check
  alias Pulse.Status

  describe "monitor_status/2" do
    test "paused when disabled, regardless of last check" do
      assert Status.monitor_status(%{enabled: false}, %Check{status: "up"}) == :paused
      assert Status.monitor_status(%{enabled: false}, nil) == :paused
    end

    test "pending when no checks have run yet" do
      assert Status.monitor_status(%{enabled: true}, nil) == :pending
    end

    test "up when latest check succeeded" do
      assert Status.monitor_status(%{enabled: true}, %Check{status: "up"}) == :up
    end

    test "down for any failure status" do
      for status <- ["down", "timeout", "error"] do
        assert Status.monitor_status(%{enabled: true}, %Check{status: status}) == :down
      end
    end
  end

  describe "heartbeat_status/2" do
    test "paused when disabled" do
      assert Status.heartbeat_status(%{enabled: false, last_pinged_at: nil}, nil) == :paused
    end

    test "missed whenever there is an open incident" do
      heartbeat = %Heartbeat{enabled: true, last_pinged_at: DateTime.utc_now()}
      assert Status.heartbeat_status(heartbeat, %{started_at: DateTime.utc_now()}) == :missed
    end

    test "pending when no ping has ever been received" do
      assert Status.heartbeat_status(%{enabled: true, last_pinged_at: nil}, nil) == :pending
    end

    test "alive when enabled, has been pinged, and no open incident" do
      heartbeat = %Heartbeat{enabled: true, last_pinged_at: DateTime.utc_now()}
      assert Status.heartbeat_status(heartbeat, nil) == :alive
    end
  end

  describe "uptime_percentage/3" do
    test "100% when there are no incidents" do
      window_start = ~U[2026-01-01 00:00:00Z]
      window_end = ~U[2026-01-02 00:00:00Z]
      assert Status.uptime_percentage([], window_start, window_end) == 100.0
    end

    test "100% for a zero-length window" do
      t = ~U[2026-01-01 00:00:00Z]
      incidents = [%{started_at: t, ended_at: nil}]
      assert Status.uptime_percentage(incidents, t, t) == 100.0
    end

    test "subtracts a fully-contained closed incident" do
      window_start = ~U[2026-01-01 00:00:00Z]
      window_end = ~U[2026-01-01 01:00:00Z]

      incidents = [
        %{started_at: ~U[2026-01-01 00:15:00Z], ended_at: ~U[2026-01-01 00:30:00Z]}
      ]

      assert Status.uptime_percentage(incidents, window_start, window_end) == 75.0
    end

    test "clips an incident that started before the window" do
      window_start = ~U[2026-01-01 00:00:00Z]
      window_end = ~U[2026-01-01 01:00:00Z]

      incidents = [
        %{started_at: ~U[2025-12-31 23:00:00Z], ended_at: ~U[2026-01-01 00:30:00Z]}
      ]

      assert Status.uptime_percentage(incidents, window_start, window_end) == 50.0
    end

    test "ignores incidents fully outside the window" do
      window_start = ~U[2026-01-01 00:00:00Z]
      window_end = ~U[2026-01-01 01:00:00Z]

      incidents = [
        %{started_at: ~U[2025-12-25 00:00:00Z], ended_at: ~U[2025-12-25 00:30:00Z]}
      ]

      assert Status.uptime_percentage(incidents, window_start, window_end) == 100.0
    end

    test "sums multiple non-overlapping incidents" do
      window_start = ~U[2026-01-01 00:00:00Z]
      window_end = ~U[2026-01-01 01:00:00Z]

      incidents = [
        %{started_at: ~U[2026-01-01 00:00:00Z], ended_at: ~U[2026-01-01 00:15:00Z]},
        %{started_at: ~U[2026-01-01 00:30:00Z], ended_at: ~U[2026-01-01 00:45:00Z]}
      ]

      assert Status.uptime_percentage(incidents, window_start, window_end) == 50.0
    end

    test "treats nil ended_at as 'still going' (capped to window_end)" do
      window_start = ~U[2026-01-01 00:00:00Z]
      window_end = ~U[2026-01-01 01:00:00Z]

      incidents = [%{started_at: ~U[2026-01-01 00:30:00Z], ended_at: nil}]

      assert Status.uptime_percentage(incidents, window_start, window_end) == 50.0
    end
  end

  describe "daily_uptime/4" do
    test "returns oldest → newest, one bucket per day" do
      now = ~U[2026-01-10 12:00:00Z]
      item = %{inserted_at: ~U[2025-01-01 00:00:00Z]}

      buckets = Status.daily_uptime(item, [], 5, now)

      assert length(buckets) == 5
      dates = Enum.map(buckets, fn {d, _} -> d end)

      assert dates == [
               ~D[2026-01-06],
               ~D[2026-01-07],
               ~D[2026-01-08],
               ~D[2026-01-09],
               ~D[2026-01-10]
             ]
    end

    test "every bucket is :up when there are no incidents" do
      now = ~U[2026-01-10 12:00:00Z]
      item = %{inserted_at: ~U[2025-01-01 00:00:00Z]}

      assert Enum.all?(Status.daily_uptime(item, [], 3, now), fn {_, b} -> b == :up end)
    end

    test "days strictly before inserted_at are :no_data" do
      now = ~U[2026-01-10 12:00:00Z]
      item = %{inserted_at: ~U[2026-01-09 00:00:00Z]}

      buckets = Status.daily_uptime(item, [], 5, now)

      assert Enum.take(buckets, 3) |> Enum.all?(fn {_, b} -> b == :no_data end)
      assert Enum.drop(buckets, 3) |> Enum.all?(fn {_, b} -> b == :up end)
    end

    test ":down when an incident covers the entire day" do
      now = ~U[2026-01-10 12:00:00Z]
      item = %{inserted_at: ~U[2025-01-01 00:00:00Z]}

      incidents = [
        %{started_at: ~U[2026-01-08 00:00:00Z], ended_at: ~U[2026-01-09 00:00:00Z]}
      ]

      buckets = Status.daily_uptime(item, incidents, 4, now)
      assert {~D[2026-01-08], :down} in buckets
      assert {~D[2026-01-09], :up} in buckets
    end

    test ":partial when an incident covers only part of the day" do
      now = ~U[2026-01-10 12:00:00Z]
      item = %{inserted_at: ~U[2025-01-01 00:00:00Z]}

      incidents = [
        %{started_at: ~U[2026-01-08 06:00:00Z], ended_at: ~U[2026-01-08 06:30:00Z]}
      ]

      buckets = Status.daily_uptime(item, incidents, 4, now)
      assert {~D[2026-01-08], :partial} in buckets
    end

    test "today's bucket only covers up to `now`" do
      now = ~U[2026-01-10 01:00:00Z]
      item = %{inserted_at: ~U[2025-01-01 00:00:00Z]}

      incidents = [
        %{started_at: ~U[2026-01-10 00:00:00Z], ended_at: ~U[2026-01-10 01:00:00Z]}
      ]

      buckets = Status.daily_uptime(item, incidents, 1, now)
      assert buckets == [{~D[2026-01-10], :down}]
    end
  end
end
