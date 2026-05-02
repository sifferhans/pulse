defmodule Pulse.Notifications.Channel do
  use Ecto.Schema
  import Ecto.Changeset

  @kinds ~w(slack discord telegram)

  schema "notification_channels" do
    field :name, :string
    field :kind, :string
    field :config, :map, default: %{}
    field :enabled, :boolean, default: true

    # Virtual fields used by the form, projected into / out of `config` on
    # changeset application.
    field :webhook_url, :string, virtual: true
    field :bot_token, :string, virtual: true
    field :chat_id, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(channel, attrs) do
    channel
    |> cast(attrs, [:name, :kind, :enabled, :webhook_url, :bot_token, :chat_id])
    |> validate_required([:name, :kind])
    |> validate_inclusion(:kind, @kinds)
    |> validate_kind_specific()
    |> build_config()
  end

  @doc "Project saved `config` map onto the virtual fields used by the form."
  def with_form_fields(%__MODULE__{config: config} = channel) when is_map(config) do
    %{
      channel
      | webhook_url: Map.get(config, "webhook_url"),
        bot_token: Map.get(config, "bot_token"),
        chat_id: Map.get(config, "chat_id")
    }
  end

  defp validate_kind_specific(changeset) do
    case get_field(changeset, :kind) do
      kind when kind in ["slack", "discord"] ->
        validate_required(changeset, [:webhook_url])

      "telegram" ->
        validate_required(changeset, [:bot_token, :chat_id])

      _ ->
        changeset
    end
  end

  defp build_config(changeset) do
    case get_field(changeset, :kind) do
      kind when kind in ["slack", "discord"] ->
        case get_field(changeset, :webhook_url) do
          nil -> changeset
          "" -> changeset
          url -> put_change(changeset, :config, %{"webhook_url" => url})
        end

      "telegram" ->
        token = get_field(changeset, :bot_token)
        chat = get_field(changeset, :chat_id)

        if token in [nil, ""] or chat in [nil, ""] do
          changeset
        else
          put_change(changeset, :config, %{"bot_token" => token, "chat_id" => chat})
        end

      _ ->
        changeset
    end
  end
end
