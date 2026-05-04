defmodule PulseWeb.Features.OverviewTest do
  use PulseWeb.ConnCase, async: false

  import Pulse.Fixtures

  setup %{conn: conn} do
    {:ok, conn: log_in_admin(conn)}
  end

  test "shows monitor and heartbeat names with status counts", %{conn: conn} do
    monitor = monitor_fixture(%{"name" => "Homepage"})
    _heartbeat = heartbeat_fixture(%{"name" => "Cron"})
    check_fixture(monitor, status: "up")

    conn
    |> visit(~p"/")
    |> assert_has("td", text: "Homepage")
    |> assert_has("td", text: "Cron")
    |> refute_has("p", text: "No monitors yet")
    |> refute_has("p", text: "No heartbeats yet")
  end

  test "navigation links jump to alerting and status pages", %{conn: conn} do
    conn
    |> visit(~p"/")
    |> click_link("Alerting")
    |> assert_path(~p"/alerting")
    |> click_link("Status pages")
    |> assert_path(~p"/status-pages")
  end
end
