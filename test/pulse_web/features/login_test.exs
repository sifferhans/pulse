defmodule PulseWeb.Features.LoginTest do
  use PulseWeb.ConnCase, async: false

  test "an unauthenticated visitor is sent to /login and can sign in", %{conn: conn} do
    conn
    |> visit(~p"/")
    |> assert_path(~p"/login")
    |> fill_in("Password", with: "test-admin-password")
    |> click_button("Sign in")
    |> assert_path(~p"/")
    |> assert_has("h2", text: "Monitors")
  end

  test "wrong password keeps the visitor on /login with an error", %{conn: conn} do
    conn
    |> visit(~p"/login")
    |> fill_in("Password", with: "wrong")
    |> click_button("Sign in")
    |> assert_path(~p"/login")
    |> assert_has("p", text: "Invalid password")
  end

  test "signed-in user can sign out", %{conn: conn} do
    conn
    |> log_in_admin()
    |> visit(~p"/")
    |> click_link("Sign out")
    |> assert_path(~p"/login")
  end
end
