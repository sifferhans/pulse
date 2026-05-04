defmodule PulseWeb.AuthTest do
  use PulseWeb.ConnCase, async: false

  alias PulseWeb.Auth

  describe "valid_password?/1" do
    test "true when the password matches the configured admin_password" do
      assert Auth.valid_password?("test-admin-password")
    end

    test "false on mismatch" do
      refute Auth.valid_password?("nope")
      refute Auth.valid_password?("")
    end

    test "false for non-binaries" do
      refute Auth.valid_password?(nil)
      refute Auth.valid_password?(1234)
    end
  end

  describe "fetch_current_admin/2" do
    test "assigns true when session has the auth flag", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{admin_authenticated: true})
        |> Auth.fetch_current_admin([])

      assert conn.assigns.current_admin?
    end

    test "assigns false when session is empty", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> Auth.fetch_current_admin([])

      refute conn.assigns.current_admin?
    end
  end

  describe "require_authenticated_admin/2" do
    test "lets authenticated users through", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> Plug.Conn.assign(:current_admin?, true)
        |> Auth.require_authenticated_admin([])

      refute conn.halted
    end

    test "redirects unauthenticated users to /login and stores the path", %{conn: conn} do
      conn =
        conn
        |> Phoenix.ConnTest.bypass_through(PulseWeb.Router, :browser)
        |> Phoenix.ConnTest.dispatch(PulseWeb.Endpoint, :get, "/")
        |> Plug.Conn.assign(:current_admin?, false)
        |> Auth.require_authenticated_admin([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/login"
      assert get_session(conn, :admin_return_to) == "/"
    end
  end
end
