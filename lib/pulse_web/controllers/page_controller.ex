defmodule PulseWeb.PageController do
  use PulseWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/monitors")
  end
end
