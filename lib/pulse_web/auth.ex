defmodule PulseWeb.Auth do
  @moduledoc """
  Single-admin authentication.

  The admin password is read from `:pulse, :admin_password` (set from the
  `PULSE_ADMIN_PASSWORD` env var in production). There are no user accounts —
  authentication is a session flag set on successful password check.
  """

  use PulseWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Phoenix.Component
  alias Phoenix.LiveView

  @session_key :admin_authenticated

  ## Login / logout

  @doc """
  Marks the session as authenticated and redirects to `return_to` (or `/`).
  Renews the session to prevent fixation.
  """
  def log_in_admin(conn, params \\ %{}) do
    return_to = get_session(conn, :admin_return_to) || ~p"/"

    conn
    |> renew_session()
    |> put_session(@session_key, true)
    |> put_session(:live_socket_id, "admin_session:#{System.unique_integer()}")
    |> maybe_remember_me(params)
    |> redirect(to: return_to)
  end

  defp maybe_remember_me(conn, _params), do: conn

  @doc "Clears the session and redirects to the login page."
  def log_out_admin(conn) do
    conn
    |> renew_session()
    |> redirect(to: ~p"/login")
  end

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  @doc """
  Validates `password` against the configured admin password using a
  constant-time comparison.
  """
  def valid_password?(password) when is_binary(password) do
    case Application.get_env(:pulse, :admin_password) do
      configured when is_binary(configured) and byte_size(configured) > 0 ->
        Plug.Crypto.secure_compare(configured, password)

      _ ->
        false
    end
  end

  def valid_password?(_), do: false

  ## Plugs

  @doc "Reads the session and assigns `:current_admin?`."
  def fetch_current_admin(conn, _opts) do
    assign(conn, :current_admin?, get_session(conn, @session_key) == true)
  end

  @doc """
  Plug to enforce authentication on a controller pipeline. Stores the
  attempted path so we can redirect back after login.
  """
  def require_authenticated_admin(conn, _opts) do
    if conn.assigns[:current_admin?] do
      conn
    else
      conn
      |> put_flash(:error, "You must sign in to access this page.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end

  @doc "Plug for the login page itself: redirect to `/` if already signed in."
  def redirect_if_authenticated(conn, _opts) do
    if conn.assigns[:current_admin?] do
      conn
      |> redirect(to: ~p"/")
      |> halt()
    else
      conn
    end
  end

  defp maybe_store_return_to(%Plug.Conn{method: "GET"} = conn) do
    put_session(conn, :admin_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn

  ## LiveView on_mount

  @doc """
  LiveView lifecycle hook. Use as:

      live_session :authenticated, on_mount: {PulseWeb.Auth, :ensure_authenticated} do
        ...
      end
  """
  def on_mount(:ensure_authenticated, _params, session, socket) do
    if session[Atom.to_string(@session_key)] == true do
      {:cont, Component.assign(socket, :current_admin?, true)}
    else
      socket =
        socket
        |> LiveView.put_flash(:error, "You must sign in to access this page.")
        |> LiveView.redirect(to: ~p"/login")

      {:halt, socket}
    end
  end
end
