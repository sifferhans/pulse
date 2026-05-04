defmodule PulseWeb.SessionControllerTest do
  use PulseWeb.ConnCase, async: false

  describe "GET /login" do
    test "renders the form", %{conn: conn} do
      conn = get(conn, ~p"/login")
      response = html_response(conn, 200)
      assert response =~ "Sign in"
      assert response =~ ~s(name="password")
    end
  end

  describe "POST /login" do
    test "with the correct password, sets the admin session and redirects to /", %{conn: conn} do
      conn = post(conn, ~p"/login", %{"password" => "test-admin-password"})
      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :admin_authenticated) == true
    end

    test "with the wrong password, re-renders with an error and no session", %{conn: conn} do
      conn = post(conn, ~p"/login", %{"password" => "nope"})
      assert html_response(conn, 200) =~ "Invalid password"
      refute get_session(conn, :admin_authenticated)
    end

    test "redirects to the stored return_to after login", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{admin_return_to: "/monitors/new"})
        |> post(~p"/login", %{"password" => "test-admin-password"})

      assert redirected_to(conn) == "/monitors/new"
    end
  end

  describe "DELETE /logout" do
    test "clears the session and redirects to /login", %{conn: conn} do
      conn =
        conn
        |> log_in_admin()
        |> delete(~p"/logout")

      assert redirected_to(conn) == ~p"/login"
      refute get_session(conn, :admin_authenticated)
    end
  end
end
