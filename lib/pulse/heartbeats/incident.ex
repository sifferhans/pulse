defmodule Pulse.Heartbeats.Incident do
  use Ecto.Schema
  import Ecto.Changeset

  schema "heartbeat_incidents" do
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec

    belongs_to :heartbeat, Pulse.Heartbeats.Heartbeat

    timestamps(type: :utc_datetime)
  end

  def changeset(incident, attrs) do
    incident
    |> cast(attrs, [:heartbeat_id, :started_at, :ended_at])
    |> validate_required([:heartbeat_id, :started_at])
    |> foreign_key_constraint(:heartbeat_id)
  end

  def open?(%__MODULE__{ended_at: nil}), do: true
  def open?(%__MODULE__{}), do: false
end
