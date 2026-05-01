defmodule Pulse.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PulseWeb.Telemetry,
      Pulse.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:pulse, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:pulse, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Pulse.PubSub},
      {Finch,
       name: Pulse.Monitoring.Finch,
       pools: %{
         default: [
           pool_max_idle_time: 1_000,
           conn_opts: [transport_opts: [timeout: 5_000]]
         ]
       }},
      {Registry, keys: :unique, name: Pulse.Monitoring.WorkerRegistry},
      Pulse.Monitoring.WorkerSupervisor,
      {Task, fn -> sync_monitoring_workers() end},
      # Start to serve requests, typically the last entry
      PulseWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Pulse.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PulseWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end

  defp sync_monitoring_workers do
    if Application.get_env(:pulse, :start_monitoring_workers, true) do
      Pulse.Monitoring.WorkerSupervisor.sync_all()
    end
  end
end
