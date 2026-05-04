defmodule Pulse.Repo.Migrations.CreateStatusPages do
  use Ecto.Migration

  def change do
    create table(:status_pages) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:status_pages, [:slug])

    create table(:status_page_monitors, primary_key: false) do
      add :status_page_id, references(:status_pages, on_delete: :delete_all), null: false
      add :monitor_id, references(:monitors, on_delete: :delete_all), null: false
    end

    create unique_index(:status_page_monitors, [:status_page_id, :monitor_id])

    create table(:status_page_heartbeats, primary_key: false) do
      add :status_page_id, references(:status_pages, on_delete: :delete_all), null: false
      add :heartbeat_id, references(:heartbeats, on_delete: :delete_all), null: false
    end

    create unique_index(:status_page_heartbeats, [:status_page_id, :heartbeat_id])
  end
end
