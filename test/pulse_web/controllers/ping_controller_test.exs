defmodule PulseWeb.PingControllerTest do
  use PulseWeb.ConnCase, async: false

  import Pulse.Fixtures

  alias Pulse.Heartbeats
  alias Pulse.Heartbeats.Heartbeat
  alias Pulse.Repo

  describe "ping/2" do
    test "GET /ping/:slug records a ping for an enabled heartbeat", %{conn: conn} do
      heartbeat = heartbeat_fixture()

      conn =
        conn
        |> put_req_header("user-agent", "curl/8.0")
        |> get(~p"/ping/#{heartbeat.slug}")

      assert response(conn, 200) =~ "OK"

      reloaded = Repo.get!(Heartbeat, heartbeat.id)
      assert reloaded.last_pinged_at != nil

      [ping | _] = Heartbeats.list_recent_pings(reloaded)
      assert ping.user_agent == "curl/8.0"
      assert ping.source_ip == "127.0.0.1"
    end

    test "POST /ping/:slug also records a ping", %{conn: conn} do
      heartbeat = heartbeat_fixture()
      conn = post(conn, ~p"/ping/#{heartbeat.slug}")
      assert response(conn, 200) =~ "OK"
      assert Repo.get!(Heartbeat, heartbeat.id).last_pinged_at != nil
    end

    test "closes any open incident on ping", %{conn: conn} do
      heartbeat = heartbeat_fixture()
      _open = heartbeat_incident_fixture(heartbeat)

      conn = get(conn, ~p"/ping/#{heartbeat.slug}")
      assert response(conn, 200) =~ "OK"

      refute Heartbeats.open_incident_for(heartbeat)
    end

    test "returns 404 for an unknown slug", %{conn: conn} do
      conn = get(conn, ~p"/ping/does-not-exist")
      assert response(conn, 404) =~ "Not Found"
    end

    test "returns 404 when the heartbeat is disabled", %{conn: conn} do
      heartbeat = heartbeat_fixture()

      heartbeat
      |> Ecto.Changeset.change(%{enabled: false})
      |> Repo.update!()

      conn = get(conn, ~p"/ping/#{heartbeat.slug}")
      assert response(conn, 404) =~ "Not Found"

      assert Repo.get!(Heartbeat, heartbeat.id).last_pinged_at == nil
    end
  end
end
