import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :pulse, Pulse.Repo,
  database: Path.expand("../pulse_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# Don't auto-spawn monitor workers during tests; tests can start them
# explicitly when needed.
config :pulse, :start_monitoring_workers, false
config :pulse, :start_heartbeat_detector, false

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :pulse, PulseWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "9pEnvtBwS4d9wAN9b1PaznhL5uR0qZ0alxfd1SYuvU+8xN8bVWrM/Dqj7R/hk1zT",
  server: false

# In test we don't send emails
config :pulse, Pulse.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
