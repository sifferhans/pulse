defmodule Pulse.Monitoring.Worker do
  @moduledoc """
  Per-monitor GenServer. Schedules itself, runs an HTTP probe, persists the
  result via `Pulse.Monitoring.record_check/1`, and updates incident state.
  """

  use GenServer, restart: :transient

  require Logger

  alias Pulse.Monitoring
  alias Pulse.Monitoring.{Monitor, Probe}

  ## API

  def child_spec(%Monitor{} = monitor) do
    %{
      id: {__MODULE__, monitor.id},
      start: {__MODULE__, :start_link, [monitor]},
      restart: :transient
    }
  end

  def start_link(%Monitor{} = monitor) do
    GenServer.start_link(__MODULE__, monitor, name: via(monitor.id))
  end

  def via(monitor_id) when is_integer(monitor_id) do
    {:via, Registry, {Pulse.Monitoring.WorkerRegistry, monitor_id}}
  end

  def whereis(monitor_id) do
    case Registry.lookup(Pulse.Monitoring.WorkerRegistry, monitor_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "Force an immediate probe (useful for tests and manual 'run now')."
  def run_now(monitor_id) do
    case whereis(monitor_id) do
      nil -> {:error, :not_running}
      pid -> GenServer.cast(pid, :run_now)
    end
  end

  ## Callbacks

  @impl true
  def init(%Monitor{} = monitor) do
    {:ok, %{monitor: monitor, timer: nil}, {:continue, :schedule_first_run}}
  end

  @impl true
  def handle_continue(:schedule_first_run, state) do
    {:noreply, schedule_next(state, 0)}
  end

  @impl true
  def handle_info(:run, state) do
    new_state = run_probe(state)
    {:noreply, schedule_next(new_state, state.monitor.interval_seconds * 1_000)}
  end

  @impl true
  def handle_cast(:run_now, state) do
    new_state = run_probe(state)
    {:noreply, schedule_next(new_state, state.monitor.interval_seconds * 1_000)}
  end

  @impl true
  def handle_call({:replace_monitor, %Monitor{} = monitor}, _from, state) do
    {:reply, :ok, schedule_next(%{state | monitor: monitor}, 0)}
  end

  defp run_probe(%{monitor: monitor} = state) do
    result = Probe.run(monitor)

    case Monitoring.record_check(Map.put(result, :monitor_id, monitor.id)) do
      {:ok, check} ->
        update_incident_state(monitor, check)

      {:error, changeset} ->
        Logger.warning(
          "Failed to persist check for monitor #{monitor.id}: #{inspect(changeset.errors)}"
        )
    end

    state
  end

  defp update_incident_state(%Monitor{} = monitor, %{status: "up"}) do
    case Monitoring.open_incident_for(monitor) do
      nil -> :ok
      incident -> Monitoring.close_incident(incident, DateTime.utc_now())
    end
  end

  defp update_incident_state(%Monitor{} = monitor, %{status: status, ran_at: ran_at, error: error})
       when status in ["down", "timeout", "error"] do
    case Monitoring.open_incident_for(monitor) do
      nil -> Monitoring.open_incident(monitor, ran_at, error)
      _existing -> :ok
    end
  end

  defp schedule_next(%{timer: nil} = state, delay_ms) do
    %{state | timer: Process.send_after(self(), :run, delay_ms)}
  end

  defp schedule_next(%{timer: timer} = state, delay_ms) do
    Process.cancel_timer(timer)
    %{state | timer: Process.send_after(self(), :run, delay_ms)}
  end
end
