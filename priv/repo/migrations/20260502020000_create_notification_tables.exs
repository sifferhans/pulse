defmodule Pulse.Repo.Migrations.CreateNotificationTables do
  use Ecto.Migration

  def change do
    create table(:notification_channels) do
      add :name, :string, null: false
      add :kind, :string, null: false
      add :config, :map, default: %{}, null: false
      add :enabled, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create table(:monitor_notification_subscriptions) do
      add :monitor_id, references(:monitors, on_delete: :delete_all), null: false

      add :channel_id, references(:notification_channels, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:monitor_notification_subscriptions, [:monitor_id, :channel_id])

    create table(:heartbeat_notification_subscriptions) do
      add :heartbeat_id, references(:heartbeats, on_delete: :delete_all), null: false

      add :channel_id, references(:notification_channels, on_delete: :delete_all),
        null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:heartbeat_notification_subscriptions, [:heartbeat_id, :channel_id])
  end
end
