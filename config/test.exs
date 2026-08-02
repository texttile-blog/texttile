import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :texttile, Texttile.Repo,
  database: Path.expand("../texttile_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# The server runs during tests so Playwright e2e tests can drive a real browser.
config :texttile, TexttileWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "8Fao2qVwktjBERHzC46IBzeQ10Ursj8/ot0xG4CIb05OT5x5KqgfzPKjmLFKFJCM",
  server: true

# Browser tests check out a DB connection via this sandbox (see Endpoint plug).
config :texttile, :sql_sandbox, Ecto.Adapters.SQL.Sandbox

config :phoenix_test,
  otp_app: :texttile,
  endpoint: TexttileWeb.Endpoint,
  playwright: [
    browser: :chromium,
    headless: true
  ]

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Each test run writes uploads into an isolated tmp directory.
config :texttile, :uploads_path, Path.expand("../tmp/test_uploads", __DIR__)
