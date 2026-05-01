defmodule Play.Repo do
  use Ecto.Repo,
    otp_app: :play,
    adapter: Ecto.Adapters.SQLite3
end
