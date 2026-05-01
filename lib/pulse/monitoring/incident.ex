defmodule Pulse.Monitoring.Incident do
  use Ecto.Schema
  import Ecto.Changeset

  schema "incidents" do
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec
    field :last_error, :string

    belongs_to :monitor, Pulse.Monitoring.Monitor

    timestamps(type: :utc_datetime)
  end

  def changeset(incident, attrs) do
    incident
    |> cast(attrs, [:monitor_id, :started_at, :ended_at, :last_error])
    |> validate_required([:monitor_id, :started_at])
    |> foreign_key_constraint(:monitor_id)
  end

  def open?(%__MODULE__{ended_at: nil}), do: true
  def open?(%__MODULE__{}), do: false
end
