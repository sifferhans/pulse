defmodule Pulse.Monitoring.Probe do
  @moduledoc """
  Pure HTTP probe for a `Pulse.Monitoring.Monitor`. Runs one request via `Req`
  and classifies the result into `{:up | :down | :timeout | :error, attrs}`
  ready for `Pulse.Monitoring.record_check/1`.
  """

  alias Pulse.Monitoring.Monitor

  @type result :: %{
          required(:status) => String.t(),
          required(:ran_at) => DateTime.t(),
          optional(:status_code) => integer() | nil,
          optional(:latency_ms) => integer() | nil,
          optional(:error) => String.t() | nil
        }

  @spec run(Monitor.t()) :: result()
  def run(%Monitor{} = monitor) do
    started_at = System.monotonic_time(:millisecond)
    ran_at = DateTime.utc_now()

    request =
      Req.new(
        method: String.to_existing_atom(String.downcase(monitor.method)),
        url: monitor.url,
        receive_timeout: monitor.timeout_ms,
        connect_options: [timeout: monitor.timeout_ms],
        retry: false,
        decode_body: false
      )

    case Req.request(request) do
      {:ok, %Req.Response{status: status_code, body: body}} ->
        latency_ms = elapsed_ms(started_at)

        cond do
          status_code != monitor.expected_status ->
            %{
              status: "down",
              status_code: status_code,
              latency_ms: latency_ms,
              ran_at: ran_at,
              error: "expected status #{monitor.expected_status}, got #{status_code}"
            }

          not body_matches?(monitor.expected_body_contains, body) ->
            %{
              status: "down",
              status_code: status_code,
              latency_ms: latency_ms,
              ran_at: ran_at,
              error: "response body did not contain #{inspect(monitor.expected_body_contains)}"
            }

          true ->
            %{
              status: "up",
              status_code: status_code,
              latency_ms: latency_ms,
              ran_at: ran_at,
              error: nil
            }
        end

      {:error, %{__exception__: true} = exception} ->
        classify_exception(exception, started_at, ran_at)
    end
  end

  defp elapsed_ms(started_at) do
    System.monotonic_time(:millisecond) - started_at
  end

  defp body_matches?(nil, _body), do: true
  defp body_matches?("", _body), do: true

  defp body_matches?(needle, body) when is_binary(needle) and is_binary(body),
    do: String.contains?(body, needle)

  defp body_matches?(_needle, _body), do: false

  defp classify_exception(exception, started_at, ran_at) do
    latency_ms = elapsed_ms(started_at)
    message = Exception.message(exception)

    status =
      case exception do
        %{reason: :timeout} -> "timeout"
        _ -> if String.contains?(message, "timeout"), do: "timeout", else: "error"
      end

    %{
      status: status,
      status_code: nil,
      latency_ms: latency_ms,
      ran_at: ran_at,
      error: String.slice(message, 0, 500)
    }
  end
end
