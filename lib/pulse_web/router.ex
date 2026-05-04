defmodule PulseWeb.Router do
  use PulseWeb, :router

  import PulseWeb.Auth, only: [fetch_current_admin: 2, require_authenticated_admin: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PulseWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_admin
  end

  pipeline :require_admin do
    plug :require_authenticated_admin
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  ## Public routes (no auth required)

  scope "/", PulseWeb do
    pipe_through :browser

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete

    live "/status/:slug", PublicStatusLive.Show, :show
  end

  scope "/ping", PulseWeb do
    match :*, "/:slug", PingController, :ping
  end

  ## Admin routes (require authentication)

  scope "/", PulseWeb do
    pipe_through [:browser, :require_admin]

    live_session :authenticated,
      on_mount: {PulseWeb.Auth, :ensure_authenticated} do
      live "/", OverviewLive.Index, :index

      live "/monitors/new", MonitorLive.Form, :new
      live "/monitors/:id", MonitorLive.Show, :show
      live "/monitors/:id/edit", MonitorLive.Form, :edit

      live "/heartbeats/new", HeartbeatLive.Form, :new
      live "/heartbeats/:id", HeartbeatLive.Show, :show
      live "/heartbeats/:id/edit", HeartbeatLive.Form, :edit

      live "/alerting", ChannelLive.Index, :index
      live "/alerting/channels/new", ChannelLive.Form, :new
      live "/alerting/channels/:id/edit", ChannelLive.Form, :edit

      live "/status-pages", StatusPageLive.Index, :index
      live "/status-pages/new", StatusPageLive.Form, :new
      live "/status-pages/:id", StatusPageLive.Show, :show
      live "/status-pages/:id/edit", StatusPageLive.Form, :edit
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", PulseWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:pulse, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PulseWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
