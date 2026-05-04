defmodule PulseWeb.SessionController do
  use PulseWeb, :controller

  alias PulseWeb.Auth

  def new(conn, _params) do
    render(conn, :new, error: nil, layout: false)
  end

  def create(conn, %{"password" => password}) do
    if Auth.valid_password?(password) do
      Auth.log_in_admin(conn)
    else
      conn
      |> put_flash(:error, "Invalid password.")
      |> render(:new, error: "Invalid password.", layout: false)
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Signed out.")
    |> Auth.log_out_admin()
  end
end
