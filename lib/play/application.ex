defmodule Play.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PlayWeb.Telemetry,
      Play.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:play, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:play, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Play.PubSub},
      {Registry, keys: :unique, name: Play.Monitoring.WorkerRegistry},
      Play.Monitoring.WorkerSupervisor,
      {Task, fn -> sync_monitoring_workers() end},
      # Start to serve requests, typically the last entry
      PlayWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Play.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PlayWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end

  defp sync_monitoring_workers do
    if Application.get_env(:play, :start_monitoring_workers, true) do
      Play.Monitoring.WorkerSupervisor.sync_all()
    end
  end
end
