defmodule PulseWeb.PublicStatusLive.Show do
  use PulseWeb, :live_view

  alias Pulse.{Heartbeats, Monitoring, StatusPages}
  alias Pulse.StatusPages.StatusPage

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case StatusPages.get_enabled_status_page_by_slug(slug) do
      nil ->
        raise Ecto.NoResultsError, queryable: StatusPage

      page ->
        if connected?(socket) do
          Monitoring.subscribe_to_monitors()
          Heartbeats.subscribe_to_heartbeats()
        end

        {:ok,
         socket
         |> assign(:page_title, page.name)
         |> assign(:status_page, page)
         |> assign(:summary, StatusPages.summarize(page)), layout: false}
    end
  end

  @impl true
  def handle_info(_msg, socket) do
    case StatusPages.get_enabled_status_page_by_slug(socket.assigns.status_page.slug) do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/")}

      page ->
        {:noreply,
         socket
         |> assign(:status_page, page)
         |> assign(:summary, StatusPages.summarize(page))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.public flash={@flash}>
      <header class="space-y-4">
        <div class="flex gap-4 items-center">
          <h1 class="text-heading-2 font-semibold text-text-default grow">
            {@status_page.name}
          </h1>
          <Layouts.theme_toggle />
        </div>
        <.banner variant={overall_variant(@summary.overall)} icon={overall_icon(@summary.overall)}>
          {overall_message(@summary.overall)}
        </.banner>
      </header>

      <.status_summary summary={@summary} />
    </Layouts.public>
    """
  end

  defp overall_variant(:up), do: "success"
  defp overall_variant(:down), do: "error"
  defp overall_variant(:pending), do: "neutral"

  defp overall_icon(:up), do: "hero-check-circle"
  defp overall_icon(:down), do: "hero-exclamation-triangle"
  defp overall_icon(:pending), do: "hero-clock"

  defp overall_message(:up), do: "All systems operational"
  defp overall_message(:down), do: "Some systems are experiencing issues"
  defp overall_message(:pending), do: "No status data yet"
end
