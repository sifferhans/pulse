defmodule Pulse.Heartbeats.Detector do
  @moduledoc """
  Wakes every #{div(30_000, 1_000)} seconds, scans for overdue heartbeats, and
  opens incidents for any whose deadline has passed without a ping.
  """

  use GenServer

  require Logger

  alias Pulse.Heartbeats

  @tick_ms 30_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    {:ok, %{}, {:continue, :tick}}
  end

  @impl true
  def handle_continue(:tick, state) do
    sweep()
    schedule_tick()
    {:noreply, state}
  end

  @impl true
  def handle_info(:tick, state) do
    sweep()
    schedule_tick()
    {:noreply, state}
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_ms)
  end

  defp sweep do
    now = DateTime.utc_now()

    Heartbeats.list_overdue(now)
    |> Enum.each(fn heartbeat ->
      case Heartbeats.open_incident(heartbeat, now) do
        {:ok, _incident} ->
          :ok

        {:error, changeset} ->
          Logger.warning(
            "Failed to open heartbeat incident for #{heartbeat.id}: #{inspect(changeset.errors)}"
          )
      end
    end)
  end
end
