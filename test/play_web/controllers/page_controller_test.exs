defmodule PlayWeb.PageControllerTest do
  use PlayWeb.ConnCase

  test "GET / redirects to /monitors", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/monitors"
  end
end
