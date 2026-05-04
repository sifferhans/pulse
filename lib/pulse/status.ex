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

  def monitor_status(_, %Check{status: status}) when status in ["down", "timeout", "error"],
    do: :down

  @spec heartbeat_status(Heartbeat.t() | %{enabled: boolean(), last_pinged_at: any()}, any()) ::
          heartbeat_status()
  def heartbeat_status(%{enabled: false}, _), do: :paused
  def heartbeat_status(_, %{} = _open_incident), do: :missed
  def heartbeat_status(%{last_pinged_at: nil}, _), do: :pending
  def heartbeat_status(_, _), do: :alive

  ## Historical aggregation

  @doc """
  Returns the uptime percentage in `[0.0, 100.0]` for the given window,
  computed as the fraction of time not covered by any incident in `incidents`.

  `incidents` is a list of structs with `:started_at` and `:ended_at` fields
  (open incidents have `nil` for `ended_at`). `window_start` and `window_end`
  bound the calculation; incidents outside the window contribute zero downtime.
  """
  @spec uptime_percentage([map()], DateTime.t(), DateTime.t()) :: float()
  def uptime_percentage(incidents, window_start, window_end) do
    total = DateTime.diff(window_end, window_start, :second)

    if total <= 0 do
      100.0
    else
      downtime =
        incidents
        |> Enum.map(&incident_overlap_seconds(&1, window_start, window_end))
        |> Enum.sum()

      max(0, total - downtime) / total * 100
    end
  end

  defp incident_overlap_seconds(%{started_at: s, ended_at: e}, window_start, window_end) do
    e = e || DateTime.utc_now()
    overlap_start = max_datetime(s, window_start)
    overlap_end = min_datetime(e, window_end)
    max(DateTime.diff(overlap_end, overlap_start, :second), 0)
  end

  defp max_datetime(a, b), do: if(DateTime.compare(a, b) == :gt, do: a, else: b)
  defp min_datetime(a, b), do: if(DateTime.compare(a, b) == :lt, do: a, else: b)

  @type day_bucket :: :up | :partial | :down | :no_data

  @doc """
  Returns a list of `{date, status}` for each of the last `days` calendar days
  in UTC, ordered oldest → newest. The status is derived from `incidents`
  intersecting that day. Days strictly before `inserted_at` return `:no_data`.

  The current day's bucket only covers `[start_of_day, now]` so it can flip
  during the day.
  """
  @spec daily_uptime(map(), [map()], pos_integer(), DateTime.t()) :: [{Date.t(), day_bucket()}]
  def daily_uptime(item, incidents, days, now \\ DateTime.utc_now()) do
    today = DateTime.to_date(now)
    inserted_at = item.inserted_at

    Enum.map((days - 1)..0//-1, fn offset ->
      date = Date.add(today, -offset)
      day_start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

      day_end =
        if Date.compare(date, today) == :eq do
          now
        else
          DateTime.new!(Date.add(date, 1), ~T[00:00:00], "Etc/UTC")
        end

      if DateTime.compare(day_end, inserted_at) != :gt do
        {date, :no_data}
      else
        effective_start = max_datetime(day_start, inserted_at)
        pct = uptime_percentage(incidents, effective_start, day_end)
        {date, bucket(pct)}
      end
    end)
  end

  defp bucket(pct) when pct >= 99.999, do: :up
  defp bucket(pct) when pct <= 0.001, do: :down
  defp bucket(_pct), do: :partial
end
