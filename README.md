# Pulse

A self-hosted uptime monitor and status-page server, built with Phoenix LiveView.

Pulse combines two complementary monitoring modes:

- **HTTP probes** — outbound checks against URLs you supply, on a fixed schedule
- **Heartbeats** — inbound pings (`POST /ping/:slug`) from cron jobs and background workers; if a ping doesn't arrive within `expected_interval + grace`, an incident is opened

Incidents notify your team over Slack, Discord, or Telegram, and roll up into public-facing status pages with 90-day uptime history.

> **Status:** early. Tagged `0.1.0`. Usable but a moving target — expect breaking changes between commits.

<!-- ![Pulse dashboard](docs/screenshots/dashboard.png) -->

## Features

- HTTP/HTTPS probes with configurable interval, timeout, expected status, body assertion, custom headers, and request body
- Heartbeat endpoints with random 96-bit slugs and a per-monitor grace window
- Incident timeline with start/end and duration
- Public status pages at `/status/:slug` showing current state and 90-day uptime bars
- Slack / Discord / Telegram notifications on incident open/close
- LiveView UI — no JS framework, no SPA build, just server-rendered HTML over a WebSocket
- Single-admin password authentication for the admin UI
- Single-binary deployment via `mix release`
- SQLite by default — no external database to operate

## Tech stack

Elixir 1.19 · Phoenix 1.8 · Phoenix LiveView 1.1 · Ecto · SQLite (via `ecto_sqlite3`) · Bandit · Tailwind · esbuild.

## Getting started

```bash
mix setup            # install deps, create + migrate db, build assets
mix phx.server       # start on http://localhost:4000
```

In development the admin password defaults to `admin`. Override with
`PULSE_ADMIN_PASSWORD=... mix phx.server` if you'd like.

Or inside an IEx session:

```bash
iex -S mix phx.server
```

### Running the test suite

```bash
mix test
mix precommit        # compile (warnings as errors), format, credo, test
```

## Production deploy

Pulse is designed to run as a single Elixir release behind a reverse proxy.

1. Generate the release scaffolding (one-time, if you haven't):

   ```bash
   mix phx.gen.release
   ```

2. Build a release:

   ```bash
   MIX_ENV=prod mix release
   ```

3. Set the required environment variables:

   | Variable | Required | Description |
   | --- | --- | --- |
   | `SECRET_KEY_BASE` | yes | Generate with `mix phx.gen.secret`. Used to sign cookies. |
   | `PULSE_ADMIN_PASSWORD` | yes | Password for the admin UI. There is one admin user and the username is implicit; treat this as a shared password. |
   | `DATABASE_PATH` | yes | Absolute path to the SQLite database file (e.g. `/var/lib/pulse/pulse.db`). |
   | `PHX_HOST` | recommended | Public hostname (used in absolute URLs). |
   | `PORT` | optional | HTTP listen port. Default `4000`. |
   | `PHX_SERVER` | yes (release) | Set to `true` to actually start the web server. |
   | `POOL_SIZE` | optional | Ecto pool size. Default `5`. |
   | `DNS_CLUSTER_QUERY` | optional | DNS-based clustering query string. |

4. Start it:

   ```bash
   PHX_SERVER=true \
   SECRET_KEY_BASE=... \
   PULSE_ADMIN_PASSWORD=... \
   DATABASE_PATH=/var/lib/pulse/pulse.db \
   PHX_HOST=pulse.example.com \
   _build/prod/rel/pulse/bin/pulse start
   ```

Migrations run automatically on boot when started as a release.

## Security & operational caveats

Read this section before exposing Pulse to the internet.

- **Single shared admin password.** Authentication is a single password set via `PULSE_ADMIN_PASSWORD`. There are no per-user accounts, no password reset, and no rate limiting on `/login`. **Strongly recommended:** put Pulse behind HTTPS and consider an additional reverse-proxy layer (Tailscale, OIDC proxy, IP allow-list) if it's exposed to the public internet. Only `/status/:slug` and `/ping/:slug` are unauthenticated; everything else requires sign-in.
- **Webhook tokens are stored unencrypted** in SQLite (`notification_channels.config`). Anyone with read access to the database file can recover Slack / Discord / Telegram credentials.
- **Heartbeat slugs are the authentication for pings.** A 96-bit random slug acts as a bearer token for `POST /ping/:slug`. Treat the URL as a secret. Slugs are not currently rotatable through the UI.
- **`/ping/:slug` has no rate limiting.** A noisy or hostile caller can fill `heartbeat_pings` indefinitely. Consider rate-limiting at the reverse proxy.
- **Outbound probes hit arbitrary URLs.** A signed-in user can point a monitor at internal addresses (link-local, metadata services, internal hostnames). Treat admin access accordingly.

## Project layout

```
lib/pulse/                 # core domain
  monitoring/              # outbound HTTP probes, workers, incidents
  heartbeats/              # inbound pings, overdue detector, incidents
  notifications/           # channel CRUD, Slack/Discord/Telegram senders, dispatcher
  status_pages/            # public status-page aggregation
  status.ex                # pure status / uptime / daily-bucket calculations
lib/pulse_web/             # LiveViews, controllers, components, router
test/                      # ExUnit tests (run with `mix test`)
```

## Contributing

Bug reports and PRs are welcome. Before submitting a PR, please run:

```bash
mix precommit
```

It enforces compile-as-errors, formatting, Credo, and the full test suite — the same gate CI uses.

## License

[MIT](LICENSE) © 2026 Sigve Hansen
