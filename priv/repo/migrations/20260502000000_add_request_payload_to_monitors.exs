defmodule Pulse.Repo.Migrations.AddRequestPayloadToMonitors do
  use Ecto.Migration

  def change do
    alter table(:monitors) do
      add :body, :text
      add :headers, :map, default: %{}, null: false
    end
  end
end
