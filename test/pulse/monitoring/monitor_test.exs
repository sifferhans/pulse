defmodule Pulse.Monitoring.MonitorTest do
  use Pulse.DataCase, async: false

  alias Pulse.Monitoring.Monitor

  defp valid_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "name" => "Example",
        "url" => "https://example.com",
        "method" => "GET",
        "interval_seconds" => 60,
        "timeout_ms" => 5_000,
        "expected_status" => 200
      },
      overrides
    )
  end

  describe "changeset/2 validation" do
    test "valid with required fields" do
      assert Monitor.changeset(%Monitor{}, valid_attrs()).valid?
    end

    test "requires name and url" do
      changeset = Monitor.changeset(%Monitor{}, %{})
      assert "can't be blank" in errors_on(changeset).name
      assert "can't be blank" in errors_on(changeset).url
    end

    test "rejects an unsupported method" do
      changeset = Monitor.changeset(%Monitor{}, valid_attrs(%{"method" => "PATCH"}))
      assert "is invalid" in errors_on(changeset).method
    end

    test "rejects an interval below 10 seconds" do
      changeset = Monitor.changeset(%Monitor{}, valid_attrs(%{"interval_seconds" => 5}))
      assert errors_on(changeset).interval_seconds != []
    end

    test "rejects a non-http URL" do
      for url <- ["ftp://example.com", "not a url"] do
        changeset = Monitor.changeset(%Monitor{}, valid_attrs(%{"url" => url}))
        assert "must be a valid http(s) URL" in errors_on(changeset).url
      end
    end

    test "rejects an expected_status outside [100, 600)" do
      changeset = Monitor.changeset(%Monitor{}, valid_attrs(%{"expected_status" => 99}))
      assert errors_on(changeset).expected_status != []

      changeset = Monitor.changeset(%Monitor{}, valid_attrs(%{"expected_status" => 600}))
      assert errors_on(changeset).expected_status != []
    end
  end

  describe "header parsing" do
    test "parses a multi-line headers_text into a map" do
      headers_text = """
      Authorization: Bearer abc
      X-Trace: 42
      """

      changeset = Monitor.changeset(%Monitor{}, valid_attrs(%{"headers_text" => headers_text}))
      assert changeset.valid?

      assert Ecto.Changeset.get_change(changeset, :headers) == %{
               "Authorization" => "Bearer abc",
               "X-Trace" => "42"
             }
    end

    test "trims whitespace and skips empty lines" do
      headers_text = "  X-One:   1  \n\n  X-Two: 2  \n"
      changeset = Monitor.changeset(%Monitor{}, valid_attrs(%{"headers_text" => headers_text}))
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :headers) == %{"X-One" => "1", "X-Two" => "2"}
    end

    test "errors on a line missing a colon" do
      changeset = Monitor.changeset(%Monitor{}, valid_attrs(%{"headers_text" => "no-colon-here"}))
      refute changeset.valid?
      assert errors_on(changeset).headers_text != []
    end

    test "errors on a line with an empty key" do
      changeset = Monitor.changeset(%Monitor{}, valid_attrs(%{"headers_text" => ": value"}))
      refute changeset.valid?
      assert errors_on(changeset).headers_text != []
    end
  end

  describe "format_headers/1" do
    test "renders a map back to sorted Key: value lines" do
      assert Monitor.format_headers(%{"B" => "2", "A" => "1"}) == "A: 1\nB: 2"
    end

    test "returns empty string for non-maps" do
      assert Monitor.format_headers(nil) == ""
    end
  end
end
