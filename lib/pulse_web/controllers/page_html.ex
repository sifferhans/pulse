defmodule PulseWeb.PageHTML do
  @moduledoc """
  This module contains pages rendered by PageController.

  See the `page_html` directory for all templates available.
  """
  use PulseWeb, :html

  embed_templates "page_html/*"

  @doc false
  def status_variant("active"), do: "success"
  def status_variant("pending"), do: "warning"
  def status_variant("inactive"), do: "neutral"
  def status_variant(_), do: "neutral"
end
