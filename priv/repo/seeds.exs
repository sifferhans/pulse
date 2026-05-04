# Demo data for screenshots and exploration. Idempotent — wipes the demo
# tables and re-seeds them every run.
#
# Usage:
#
#     mix run priv/repo/seeds.exs

alias Pulse.Heartbeats.{Heartbeat, Incident, Ping}
alias Pulse.Monitoring.{Check, Monitor}
alias Pulse.Notifications.Channel
alias Pulse.Repo
alias Pulse.StatusPages
alias Pulse.StatusPages.StatusPage

# ─── Wipe existing data ─────────────────────────────────────────────────────

Repo.delete_all(Check)
Repo.delete_all(Pulse.Monitoring.Incident)
Repo.delete_all(Ping)
Repo.delete_all(Incident)
Repo.delete_all(StatusPage)
Repo.delete_all(Monitor)
Repo.delete_all(Heartbeat)
Repo.delete_all(Channel)

# `*_usec` fields keep microsecond precision; plain `:utc_datetime`
# (`inserted_at`/`updated_at`) must be truncated.
now_usec = DateTime.utc_now()
now_sec = DateTime.truncate(now_usec, :second)
now = now_usec
sec = fn dt -> DateTime.truncate(dt, :second) end

# Insert a struct directly (bypassing context broadcasts, so we don't spam
# PubSub during seeding).
insert! = fn schema, attrs ->
  schema
  |> struct(attrs)
  |> Repo.insert!()
end

# ─── Notification channels ──────────────────────────────────────────────────
# Disabled by default because the webhook URLs are fake. Flip them on after
# you've replaced the webhook with a real one.

slack =
  insert!.(Channel, %{
    name: "Engineering · #ops",
    kind: "slack",
    config: %{"webhook_url" => "https://hooks.slack.com/services/T0000/B0000/replace-me"},
    enabled: false,
    inserted_at: sec.(DateTime.add(now, -7, :day)),
    updated_at: now_sec
  })

_discord =
  insert!.(Channel, %{
    name: "Discord · alerts",
    kind: "discord",
    config: %{"webhook_url" => "https://discord.com/api/webhooks/000/replace-me"},
    enabled: false,
    inserted_at: sec.(DateTime.add(now, -7, :day)),
    updated_at: now_sec
  })

# ─── Monitors ───────────────────────────────────────────────────────────────

# Helpers to fabricate a believable check history and a few past incidents.
seed_check_history = fn monitor, opts ->
  count = Keyword.get(opts, :count, 50)
  base_latency = Keyword.get(opts, :base_latency, 120)
  jitter = Keyword.get(opts, :jitter, 60)
  # how many of the last `count` checks to mark as failed
  failures = Keyword.get(opts, :failures, 0)

  for i <- (count - 1)..0//-1 do
    ran_at = DateTime.add(now, -i * monitor.interval_seconds, :second)
    failed? = i < failures
    latency = base_latency + :rand.uniform(jitter * 2) - jitter

    attrs = %{
      monitor_id: monitor.id,
      ran_at: ran_at,
      inserted_at: sec.(ran_at),
      latency_ms: max(latency, 5),
      status: if(failed?, do: "down", else: "up"),
      status_code: if(failed?, do: 503, else: monitor.expected_status),
      error: if(failed?, do: "expected status 200, got 503", else: nil)
    }

    insert!.(Check, attrs)
  end
end

seed_closed_incident = fn monitor, started_offset_minutes, duration_minutes ->
  started = DateTime.add(now, -started_offset_minutes * 60, :second)
  ended = DateTime.add(started, duration_minutes * 60, :second)

  insert!.(Pulse.Monitoring.Incident, %{
    monitor_id: monitor.id,
    started_at: started,
    ended_at: ended,
    last_error: "Connection timed out",
    inserted_at: sec.(started),
    updated_at: sec.(ended)
  })
end

seed_open_incident = fn monitor, started_offset_minutes, error ->
  started = DateTime.add(now, -started_offset_minutes * 60, :second)

  insert!.(Pulse.Monitoring.Incident, %{
    monitor_id: monitor.id,
    started_at: started,
    last_error: error,
    inserted_at: sec.(started),
    updated_at: sec.(started)
  })
end

# ─── Healthy monitors ───────────────────────────────────────────────────────

api =
  insert!.(Monitor, %{
    name: "API · production",
    url: "https://httpbin.org/status/200",
    method: "GET",
    interval_seconds: 60,
    timeout_ms: 5_000,
    expected_status: 200,
    enabled: true,
    inserted_at: sec.(DateTime.add(now, -30, :day)),
    updated_at: now_sec
  })

seed_check_history.(api, count: 60, base_latency: 110, jitter: 40)
seed_closed_incident.(api, 60 * 24 * 2, 7)

marketing =
  insert!.(Monitor, %{
    name: "Marketing site",
    url: "https://example.com",
    method: "GET",
    interval_seconds: 120,
    timeout_ms: 5_000,
    expected_status: 200,
    enabled: true,
    inserted_at: sec.(DateTime.add(now, -45, :day)),
    updated_at: now_sec
  })

seed_check_history.(marketing, count: 60, base_latency: 230, jitter: 80)

cdn =
  insert!.(Monitor, %{
    name: "Image CDN",
    url: "https://httpbin.org/status/200",
    method: "HEAD",
    interval_seconds: 30,
    timeout_ms: 3_000,
    expected_status: 200,
    enabled: true,
    inserted_at: sec.(DateTime.add(now, -14, :day)),
    updated_at: now_sec
  })

seed_check_history.(cdn, count: 80, base_latency: 45, jitter: 20)

# ─── A degraded monitor (currently up but with a recent incident) ───────────

webhooks =
  insert!.(Monitor, %{
    name: "Webhooks ingest",
    url: "https://httpbin.org/status/200",
    method: "POST",
    interval_seconds: 60,
    timeout_ms: 5_000,
    expected_status: 200,
    body: ~s({"ping": true}),
    headers: %{"Content-Type" => "application/json"},
    enabled: true,
    inserted_at: sec.(DateTime.add(now, -10, :day)),
    updated_at: now_sec
  })

seed_check_history.(webhooks, count: 50, base_latency: 180, jitter: 60)
seed_closed_incident.(webhooks, 90, 12)
seed_closed_incident.(webhooks, 60 * 24, 25)

# ─── A currently-down monitor ───────────────────────────────────────────────
# Points at a 503 endpoint so real probes keep it red after the seeds are
# overwritten by the worker.

billing =
  insert!.(Monitor, %{
    name: "Billing service",
    url: "https://httpbin.org/status/503",
    method: "GET",
    interval_seconds: 60,
    timeout_ms: 5_000,
    expected_status: 200,
    enabled: true,
    inserted_at: sec.(DateTime.add(now, -20, :day)),
    updated_at: now_sec
  })

seed_check_history.(billing, count: 50, base_latency: 200, jitter: 50, failures: 5)
seed_open_incident.(billing, 7, "expected status 200, got 503")

# ─── Heartbeats ─────────────────────────────────────────────────────────────

alive_heartbeat = fn name, interval, grace, last_ping_minutes_ago ->
  hb =
    insert!.(Heartbeat, %{
      name: name,
      slug: Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false),
      expected_interval_seconds: interval,
      grace_seconds: grace,
      enabled: true,
      last_pinged_at: DateTime.add(now, -last_ping_minutes_ago * 60, :second),
      inserted_at: sec.(DateTime.add(now, -30, :day)),
      updated_at: now_sec
    })

  for i <- 0..6 do
    pinged_at = DateTime.add(now, -(last_ping_minutes_ago + i * div(interval, 60)) * 60, :second)

    insert!.(Ping, %{
      heartbeat_id: hb.id,
      pinged_at: pinged_at,
      inserted_at: sec.(pinged_at),
      source_ip: "10.0.0.#{:rand.uniform(254)}",
      user_agent: "curl/8.0"
    })
  end

  hb
end

nightly = alive_heartbeat.("Nightly backup", 86_400, 600, 60 * 4)
hourly = alive_heartbeat.("Cache warmer (hourly)", 3_600, 120, 12)
weekly_report = alive_heartbeat.("Weekly billing report", 7 * 86_400, 3_600, 60 * 36)

# Missed heartbeat: deadline passed, with an open incident.
late_export =
  insert!.(Heartbeat, %{
    name: "Analytics export",
    slug: Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false),
    expected_interval_seconds: 3_600,
    grace_seconds: 300,
    enabled: true,
    last_pinged_at: DateTime.add(now, -3 * 3_600, :second),
    inserted_at: sec.(DateTime.add(now, -10, :day)),
    updated_at: now_sec
  })

insert!.(Incident, %{
  heartbeat_id: late_export.id,
  started_at: DateTime.add(now, -2 * 3_600, :second),
  inserted_at: sec.(DateTime.add(now, -2 * 3_600, :second)),
  updated_at: now_sec
})

# Pending heartbeat (never pinged).
_pending =
  insert!.(Heartbeat, %{
    name: "Migration job (new)",
    slug: Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false),
    expected_interval_seconds: 600,
    grace_seconds: 60,
    enabled: true,
    inserted_at: now_sec,
    updated_at: now_sec
  })

# ─── Public status page ─────────────────────────────────────────────────────

{:ok, _page} =
  StatusPages.create_status_page(%{
    name: "Pulse Demo",
    enabled: true,
    monitor_ids: [api.id, marketing.id, cdn.id, webhooks.id, billing.id],
    heartbeat_ids: [nightly.id, hourly.id, weekly_report.id, late_export.id]
  })

# Avoid the unused-variable warning for the channel we kept a reference to.
_ = slack

monitor_count = Repo.aggregate(Monitor, :count)
heartbeat_count = Repo.aggregate(Heartbeat, :count)
status_page_count = Repo.aggregate(StatusPage, :count)

IO.puts("""
Seeded:
  · #{monitor_count} monitors (one currently down)
  · #{heartbeat_count} heartbeats (one missed, one pending)
  · #{status_page_count} public status page (visit /status/<slug> on the dashboard)

Tip: monitors are enabled, so the worker will start probing within ~60s of
boot and may overwrite the most recent fabricated check. Take screenshots
soon after running seeds (or set `enabled: false` on a monitor to freeze its
last-known status).
""")
