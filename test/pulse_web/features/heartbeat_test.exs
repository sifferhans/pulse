defmodule PulseWeb.Features.HeartbeatTest do
  use PulseWeb.ConnCase, async: false

  import Pulse.Fixtures

  setup %{conn: conn} do
    {:ok, conn: log_in_admin(conn)}
  end

  test "creating a heartbeat lands on its show page", %{conn: conn} do
    conn
    |> visit(~p"/heartbeats/new")
    |> fill_in("Name", with: "Nightly export")
    |> click_button("Save heartbeat")
    |> assert_has("h1", text: "Nightly export")
  end

  test "show page displays the ping URL containing the slug", %{conn: conn} do
    heartbeat = heartbeat_fixture(%{"name" => "Cron job"})

    conn
    |> visit(~p"/heartbeats/#{heartbeat.id}")
    |> assert_has("h1", text: "Cron job")
    |> assert_has("*", text: heartbeat.slug)
  end

  test "form re-renders with errors on invalid interval", %{conn: conn} do
    conn
    |> visit(~p"/heartbeats/new")
    |> fill_in("Name", with: "Too fast")
    |> fill_in("Expected interval (seconds)", with: "5")
    |> click_button("Save heartbeat")
    |> assert_path(~p"/heartbeats/new")
    |> assert_has("p", text: "must be greater than or equal to 30")
  end
end
