defmodule Play.Repo.Migrations.CreateMonitoringTables do
  use Ecto.Migration

  def change do
    create table(:monitors) do
      add :name, :string, null: false
      add :url, :string, null: false
      add :method, :string, null: false, default: "GET"
      add :interval_seconds, :integer, null: false, default: 60
      add :timeout_ms, :integer, null: false, default: 5_000
      add :expected_status, :integer, null: false, default: 200
      add :expected_body_contains, :string
      add :enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create table(:checks) do
      add :monitor_id, references(:monitors, on_delete: :delete_all), null: false
      add :status, :string, null: false
      add :latency_ms, :integer
      add :status_code, :integer
      add :error, :string
      add :ran_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:checks, [:monitor_id, :ran_at])

    create table(:incidents) do
      add :monitor_id, references(:monitors, on_delete: :delete_all), null: false
      add :started_at, :utc_datetime_usec, null: false
      add :ended_at, :utc_datetime_usec
      add :last_error, :string

      timestamps(type: :utc_datetime)
    end

    create index(:incidents, [:monitor_id, :ended_at])
  end
end
