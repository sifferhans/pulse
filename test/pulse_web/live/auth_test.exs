defmodule PulseWeb.LiveAuthTest do
  use PulseWeb.ConnCase, async: true

  describe "admin LiveView routes" do
    test "redirect to /login when unauthenticated", %{conn: conn} do
      for path <- ["/", "/monitors/new", "/heartbeats/new", "/alerting", "/status-pages"] do
        assert {:error, {:redirect, %{to: "/login"}}} = live(conn, path)
      end
    end

    test "render successfully when authenticated", %{conn: conn} do
      conn = log_in_admin(conn)
      {:ok, _view, html} = live(conn, ~p"/")
      assert html =~ "Pulse"
    end
  end

  describe "public routes" do
    test "/status/:slug is reachable without auth", %{conn: conn} do
      {:ok, page} = Pulse.StatusPages.create_status_page(%{name: "Public", enabled: true})
      assert {:ok, _view, _html} = live(conn, ~p"/status/#{page.slug}")
    end
  end
end
