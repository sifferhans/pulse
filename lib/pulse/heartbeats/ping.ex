defmodule Pulse.Heartbeats.Ping do
  use Ecto.Schema
  import Ecto.Changeset

  schema "heartbeat_pings" do
    field :pinged_at, :utc_datetime_usec
    field :source_ip, :string
    field :user_agent, :string

    belongs_to :heartbeat, Pulse.Heartbeats.Heartbeat

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def changeset(ping, attrs) do
    ping
    |> cast(attrs, [:heartbeat_id, :pinged_at, :source_ip, :user_agent])
    |> validate_required([:heartbeat_id, :pinged_at])
    |> foreign_key_constraint(:heartbeat_id)
  end
end
