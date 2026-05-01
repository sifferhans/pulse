defmodule PulseWeb.PageControllerTest do
  use PulseWeb.ConnCase

  test "GET / redirects to /monitors", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/monitors"
  end
end
