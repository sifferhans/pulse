defmodule PulseWeb.Features.MonitorTest do
  use PulseWeb.ConnCase, async: false

  import Pulse.Fixtures

  setup %{conn: conn} do
    {:ok, conn: log_in_admin(conn)}
  end

  test "the empty dashboard shows an empty state and a CTA", %{conn: conn} do
    conn
    |> visit(~p"/")
    |> assert_has("h2", text: "Monitors")
    |> assert_has("p", text: "No monitors yet")
    |> click_link("New monitor")
    |> assert_path(~p"/monitors/new")
  end

  test "creating a monitor lands on its show page and lists it on the dashboard", %{conn: conn} do
    conn
    |> visit(~p"/monitors/new")
    |> fill_in("Name", with: "API health")
    |> fill_in("URL", with: "https://example.com/health")
    |> click_button("Save monitor")
    |> assert_has("h1", text: "API health")
    |> visit(~p"/")
    |> assert_has("td", text: "API health")
    |> assert_has("td", text: "https://example.com/health")
  end

  test "the form re-renders with errors when the URL is invalid", %{conn: conn} do
    conn
    |> visit(~p"/monitors/new")
    |> fill_in("Name", with: "Broken")
    |> fill_in("URL", with: "ftp://nope")
    |> click_button("Save monitor")
    |> assert_path(~p"/monitors/new")
    |> assert_has("p", text: "must be a valid http(s) URL")
  end

  test "edit form is pre-filled with the monitor's current values", %{conn: conn} do
    monitor = monitor_fixture(%{"name" => "Original"})

    conn
    |> visit(~p"/monitors/#{monitor.id}/edit")
    |> assert_has("input[name='monitor[name]'][value='Original']")
    |> fill_in("Name", with: "Renamed")
    |> click_button("Save monitor")
    |> assert_has("h1", text: "Renamed")
  end
end
