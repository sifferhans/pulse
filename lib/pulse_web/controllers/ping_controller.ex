defmodule PulseWeb.PingController do
  use PulseWeb, :controller

  alias Pulse.Heartbeats

  def ping(conn, %{"slug" => slug}) do
    case Heartbeats.get_heartbeat_by_slug(slug) do
      %Heartbeats.Heartbeat{enabled: true} = heartbeat ->
        Heartbeats.record_ping(heartbeat, %{
          source_ip: format_ip(conn.remote_ip),
          user_agent: get_user_agent(conn)
        })

        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(200, "OK\n")

      _ ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "Not Found\n")
    end
  end

  defp format_ip(nil), do: nil

  defp format_ip(ip) when is_tuple(ip) do
    case :inet.ntoa(ip) do
      {:error, _} -> nil
      addr -> to_string(addr)
    end
  end

  defp format_ip(_), do: nil

  defp get_user_agent(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [ua | _] -> ua
      [] -> nil
    end
  end
end
