defmodule Pulse.Monitoring.Monitor do
  use Ecto.Schema
  import Ecto.Changeset

  @methods ~w(GET POST HEAD)

  @type t :: %__MODULE__{}

  schema "monitors" do
    field :name, :string
    field :url, :string
    field :method, :string, default: "GET"
    field :interval_seconds, :integer, default: 60
    field :timeout_ms, :integer, default: 5_000
    field :expected_status, :integer, default: 200
    field :expected_body_contains, :string
    field :body, :string
    field :headers, :map, default: %{}
    field :headers_text, :string, virtual: true
    field :enabled, :boolean, default: true

    has_many :checks, Pulse.Monitoring.Check, preload_order: [desc: :ran_at]
    has_many :incidents, Pulse.Monitoring.Incident

    many_to_many :channels, Pulse.Notifications.Channel,
      join_through: "monitor_notification_subscriptions",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def methods, do: @methods

  @doc """
  Render a headers map back into the multi-line `Key: value` form used by the
  edit form's textarea.
  """
  def format_headers(headers) when is_map(headers) do
    headers
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map_join("\n", fn {k, v} -> "#{k}: #{v}" end)
  end

  def format_headers(_), do: ""

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
      :body,
      :headers_text,
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
    |> parse_headers()
  end

  defp parse_headers(changeset) do
    case fetch_change(changeset, :headers_text) do
      :error ->
        changeset

      {:ok, text} when is_binary(text) ->
        case do_parse_headers(text) do
          {:ok, map} -> put_change(changeset, :headers, map)
          {:error, line} -> add_error(changeset, :headers_text, "invalid header line: #{line}")
        end

      {:ok, _} ->
        changeset
    end
  end

  defp do_parse_headers(text) do
    text
    |> String.split(["\r\n", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce_while({:ok, %{}}, &parse_header_line/2)
  end

  defp parse_header_line(line, {:ok, acc}) do
    case String.split(line, ":", parts: 2) do
      [key, value] ->
        case {String.trim(key), String.trim(value)} do
          {"", _} -> {:halt, {:error, line}}
          {k, v} -> {:cont, {:ok, Map.put(acc, k, v)}}
        end

      _ ->
        {:halt, {:error, line}}
    end
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
