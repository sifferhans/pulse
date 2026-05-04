defmodule Pulse.Fixtures do
  @moduledoc false

  alias Pulse.Heartbeats
  alias Pulse.Heartbeats.{Heartbeat, Incident, Ping}
  alias Pulse.Monitoring
  alias Pulse.Monitoring.{Check, Monitor}
  alias Pulse.Notifications
  alias Pulse.Repo

  def monitor_attrs(attrs \\ %{}) do
    Map.merge(
      %{
        "name" => "Example",
        "url" => "https://example.com",
        "method" => "GET",
        "interval_seconds" => 60,
        "timeout_ms" => 5_000,
        "expected_status" => 200
      },
      stringify_keys(attrs)
    )
  end

  def monitor_fixture(attrs \\ %{}) do
    {:ok, monitor} = Monitoring.create_monitor(monitor_attrs(attrs))
    monitor
  end

  def heartbeat_attrs(attrs \\ %{}) do
    Map.merge(
      %{
        "name" => "Nightly Job",
        "expected_interval_seconds" => 300,
        "grace_seconds" => 60
      },
      stringify_keys(attrs)
    )
  end

  def heartbeat_fixture(attrs \\ %{}) do
    {:ok, heartbeat} = Heartbeats.create_heartbeat(heartbeat_attrs(attrs))
    heartbeat
  end

  def channel_attrs(attrs \\ %{}) do
    Map.merge(
      %{
        "name" => "Slack #ops",
        "kind" => "slack",
        "webhook_url" => "https://hooks.slack.com/services/T0/B0/abc"
      },
      stringify_keys(attrs)
    )
  end

  def channel_fixture(attrs \\ %{}) do
    {:ok, channel} = Notifications.create_channel(channel_attrs(attrs))
    channel
  end

  def check_fixture(%Monitor{} = monitor, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          monitor_id: monitor.id,
          status: "up",
          ran_at: DateTime.utc_now()
        },
        Map.new(attrs)
      )

    %Check{}
    |> Check.changeset(attrs)
    |> Repo.insert!()
  end

  def monitor_incident_fixture(%Monitor{} = monitor, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          monitor_id: monitor.id,
          started_at: DateTime.utc_now(),
          last_error: "boom"
        },
        Map.new(attrs)
      )

    %Pulse.Monitoring.Incident{}
    |> Pulse.Monitoring.Incident.changeset(attrs)
    |> Repo.insert!()
  end

  def heartbeat_incident_fixture(%Heartbeat{} = heartbeat, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{heartbeat_id: heartbeat.id, started_at: DateTime.utc_now()},
        Map.new(attrs)
      )

    %Incident{}
    |> Incident.changeset(attrs)
    |> Repo.insert!()
  end

  def ping_fixture(%Heartbeat{} = heartbeat, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{heartbeat_id: heartbeat.id, pinged_at: DateTime.utc_now()},
        Map.new(attrs)
      )

    %Ping{}
    |> Ping.changeset(attrs)
    |> Repo.insert!()
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
