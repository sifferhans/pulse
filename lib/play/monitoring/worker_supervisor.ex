defmodule Play.Monitoring.WorkerSupervisor do
  @moduledoc """
  DynamicSupervisor that owns one `Play.Monitoring.Worker` per enabled monitor.
  """

  use DynamicSupervisor

  alias Play.Monitoring
  alias Play.Monitoring.{Monitor, Worker}

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc "Start a worker for a monitor; returns `:ok` whether starting or already started."
  def ensure_started(%Monitor{} = monitor) do
    case DynamicSupervisor.start_child(__MODULE__, Worker.child_spec(monitor)) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, _} = error -> error
    end
  end

  @doc "Stop a worker if running."
  def stop(monitor_id) do
    case Worker.whereis(monitor_id) do
      nil ->
        :ok

      pid ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  @doc """
  Sync running workers with database state. Starts workers for newly-enabled
  monitors, stops workers for disabled or deleted ones, and pushes config
  updates to existing workers.
  """
  def sync_all do
    enabled = Monitoring.list_enabled_monitors()
    enabled_ids = MapSet.new(enabled, & &1.id)

    running_ids =
      Registry.select(Play.Monitoring.WorkerRegistry, [
        {{:"$1", :_, :_}, [], [:"$1"]}
      ])
      |> MapSet.new()

    Enum.each(MapSet.difference(running_ids, enabled_ids), &stop/1)

    Enum.each(enabled, fn monitor ->
      case Worker.whereis(monitor.id) do
        nil -> ensure_started(monitor)
        pid -> GenServer.call(pid, {:replace_monitor, monitor})
      end
    end)

    :ok
  end
end
