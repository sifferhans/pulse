defmodule Play.Monitoring.Monitor do
  use Ecto.Schema
  import Ecto.Changeset

  @methods ~w(GET POST HEAD)

  schema "monitors" do
    field :name, :string
    field :url, :string
    field :method, :string, default: "GET"
    field :interval_seconds, :integer, default: 60
    field :timeout_ms, :integer, default: 5_000
    field :expected_status, :integer, default: 200
    field :expected_body_contains, :string
    field :enabled, :boolean, default: true

    has_many :checks, Play.Monitoring.Check, preload_order: [desc: :ran_at]
    has_many :incidents, Play.Monitoring.Incident

    timestamps(type: :utc_datetime)
  end

  def methods, do: @methods

  def changeset(monitor, attrs) do
    monitor
    |> cast(attrs, [
      :name,
      :url,
      :method,
      :interval_seconds,
      :timeout_ms,
      :expected_status,
      :expected_body_contains,
      :enabled
    ])
    |> validate_required([:name, :url, :method, :interval_seconds, :timeout_ms, :expected_status])
    |> validate_inclusion(:method, @methods)
    |> validate_number(:interval_seconds,
      greater_than_or_equal_to: 10,
      less_than_or_equal_to: 86_400
    )
    |> validate_number(:timeout_ms, greater_than_or_equal_to: 100, less_than_or_equal_to: 60_000)
    |> validate_number(:expected_status, greater_than_or_equal_to: 100, less_than: 600)
    |> validate_url(:url)
  end

  defp validate_url(changeset, field) do
    validate_change(changeset, field, fn ^field, value ->
      case URI.new(value) do
        {:ok, %URI{scheme: scheme, host: host}}
        when scheme in ["http", "https"] and is_binary(host) and host != "" ->
          []

        _ ->
          [{field, "must be a valid http(s) URL"}]
      end
    end)
  end
end
