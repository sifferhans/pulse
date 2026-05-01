defmodule PlayWeb.PageController do
  use PlayWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/monitors")
  end
end
