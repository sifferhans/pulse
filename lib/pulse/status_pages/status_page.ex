defmodule Pulse.StatusPages.StatusPage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "status_pages" do
    field :name, :string
    field :slug, :string
    field :enabled, :boolean, default: true

    many_to_many :monitors, Pulse.Monitoring.Monitor,
      join_through: "status_page_monitors",
      on_replace: :delete

    many_to_many :heartbeats, Pulse.Heartbeats.Heartbeat,
      join_through: "status_page_heartbeats",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def changeset(status_page, attrs) do
    status_page
    |> cast(attrs, [:name, :enabled])
    |> validate_required([:name])
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
