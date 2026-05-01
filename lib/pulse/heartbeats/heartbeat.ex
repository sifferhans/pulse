defmodule Pulse.Heartbeats.Heartbeat do
  use Ecto.Schema
  import Ecto.Changeset

  schema "heartbeats" do
    field :name, :string
    field :slug, :string
    field :expected_interval_seconds, :integer, default: 300
    field :grace_seconds, :integer, default: 60
    field :enabled, :boolean, default: true
    field :last_pinged_at, :utc_datetime_usec

    has_many :pings, Pulse.Heartbeats.Ping, preload_order: [desc: :pinged_at]
    has_many :incidents, Pulse.Heartbeats.Incident

    timestamps(type: :utc_datetime)
  end

  def changeset(heartbeat, attrs) do
    heartbeat
    |> cast(attrs, [:name, :expected_interval_seconds, :grace_seconds, :enabled])
    |> validate_required([:name, :expected_interval_seconds, :grace_seconds])
    |> validate_number(:expected_interval_seconds,
      greater_than_or_equal_to: 30,
      less_than_or_equal_to: 86_400
    )
    |> validate_number(:grace_seconds,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 3_600
    )
    |> ensure_slug()
    |> unique_constraint(:slug)
  end

  defp ensure_slug(changeset) do
    case get_field(changeset, :slug) do
      nil -> put_change(changeset, :slug, generate_slug())
      _ -> changeset
    end
  end

  defp generate_slug do
    Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
  end
end
