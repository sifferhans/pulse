defmodule Pulse.Monitoring.Check do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(up down timeout error)

  schema "checks" do
    field :status, :string
    field :latency_ms, :integer
    field :status_code, :integer
    field :error, :string
    field :ran_at, :utc_datetime_usec

    belongs_to :monitor, Pulse.Monitoring.Monitor

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def statuses, do: @statuses

  def changeset(check, attrs) do
    check
    |> cast(attrs, [:monitor_id, :status, :latency_ms, :status_code, :error, :ran_at])
    |> validate_required([:monitor_id, :status, :ran_at])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:monitor_id)
  end
end
