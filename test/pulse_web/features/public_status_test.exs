defmodule PulseWeb.Features.PublicStatusTest do
  use PulseWeb.ConnCase, async: false

  alias Pulse.StatusPages

  test "the public status page renders without auth and shows the configured name", %{conn: conn} do
    {:ok, page} = StatusPages.create_status_page(%{name: "Public Pulse", enabled: true})

    conn
    |> visit(~p"/status/#{page.slug}")
    |> assert_has("h1", text: "Public Pulse")
  end

  test "a disabled status page returns 404", %{conn: conn} do
    {:ok, page} =
      StatusPages.create_status_page(%{name: "Hidden", enabled: false})

    assert_error_sent 404, fn -> get(conn, ~p"/status/#{page.slug}") end
  end
end
