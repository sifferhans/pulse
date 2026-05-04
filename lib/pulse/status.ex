defmodule Pulse.Status do
  @moduledoc """
  Shared status computation for monitors and heartbeats. Returns atoms that
  the `status_badge` component renders identically across the Overview and
  public status pages.
  """

  alias Pulse.Heartbeats.Heartbeat
  alias Pulse.Monitoring.{Check, Monitor}

  @type monitor_status :: :up | :down | :pending | :paused
  @type heartbeat_status :: :alive | :missed | :pending | :paused

  @spec monitor_status(Monitor.t() | %{enabled: boolean()}, Check.t() | nil) :: monitor_status()
  def monitor_status(%{enabled: false}, _), do: :paused
  def monitor_status(_, nil), do: :pending
  def monitor_status(_, %Check{status: "up"}), do: :up
  def monitor_status(_, %Check{status: status}) when status in ["down", "timeout", "error"], do: :down

  @spec heartbeat_status(Heartbeat.t() | %{enabled: boolean(), last_pinged_at: any()}, any()) ::
          heartbeat_status()
  def heartbeat_status(%{enabled: false}, _), do: :paused
  def heartbeat_status(_, %{} = _open_incident), do: :missed
  def heartbeat_status(%{last_pinged_at: nil}, _), do: :pending
  def heartbeat_status(_, _), do: :alive
end
