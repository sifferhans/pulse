defmodule Pulse.Repo.Migrations.CreateHeartbeatTables do
  use Ecto.Migration

  def change do
    create table(:heartbeats) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :expected_interval_seconds, :integer, null: false, default: 300
      add :grace_seconds, :integer, null: false, default: 60
      add :enabled, :boolean, null: false, default: true
      add :last_pinged_at, :utc_datetime_usec

      timestamps(type: :utc_datetime)
    end

    create unique_index(:heartbeats, [:slug])

    create table(:heartbeat_pings) do
      add :heartbeat_id, references(:heartbeats, on_delete: :delete_all), null: false
      add :pinged_at, :utc_datetime_usec, null: false
      add :source_ip, :string
      add :user_agent, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:heartbeat_pings, [:heartbeat_id, :pinged_at])

    create table(:heartbeat_incidents) do
      add :heartbeat_id, references(:heartbeats, on_delete: :delete_all), null: false
      add :started_at, :utc_datetime_usec, null: false
      add :ended_at, :utc_datetime_usec

      timestamps(type: :utc_datetime)
    end

    create index(:heartbeat_incidents, [:heartbeat_id, :ended_at])
  end
end
