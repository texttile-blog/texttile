import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
# Tests set the names they need (see Texttile.AccountsFixtures).
config :texttile, :admin_users, []

config :texttile, Texttile.Repo,
  database: Path.expand("../texttile_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox,
  # How long a test waits for the write lock of the test before it. The default
  # of 2 seconds is thin on a loaded CI machine. See
  # `Texttile.DataCase.take_write_lock/0`.
  busy_timeout: 5_000

# The server runs during tests so Playwright e2e tests can drive a real browser.
config :texttile, TexttileWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("TEST_PORT") || "4440")],
  secret_key_base: "8Fao2qVwktjBERHzC46IBzeQ10Ursj8/ot0xG4CIb05OT5x5KqgfzPKjmLFKFJCM",
  server: true

# Browser tests check out a DB connection via this sandbox (see Endpoint plug).
config :texttile, :sql_sandbox, Ecto.Adapters.SQL.Sandbox

config :phoenix_test,
  otp_app: :texttile,
  endpoint: TexttileWeb.Endpoint,
  playwright: [
    browser: :chromium,
    headless: true,
    # How long the browser waits for what a test asks for. The default
    # two seconds fit a developer machine; the CI runner has two cores
    # for the server, the browser and SQLite together, and a page that
    # mounts a LiveView first can take longer than that. The ceiling
    # only costs time where something is broken anyway.
    timeout: 10_000
  ]

# The backup limit is 600 a minute in life, which no test would reach
# without spending a minute reaching it.
config :texttile, :backup_per_minute, 12

# A browser test types faster than a person, so the comment form's time
# trap stands down. The tests about the trap set the age themselves.

# The subscriber mails go to a test mailbox that no provider counts, so
# they leave without the pause that paces a real send.
config :texttile, :newsletter_pace_ms, 0

# The importer's HTTP requests answer from a stub instead of the net,
# so its stub hosts must not be resolved and judged.
config :texttile, :import_req_options, plug: {Req.Test, Texttile.ImportStub}
config :texttile, :import_allow_private_hosts, true

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

# Mails are captured in-process, never sent.
config :texttile, Texttile.Mailer, adapter: Swoosh.Adapters.Test
config :swoosh, :api_client, false

# Fast password hashing; tests never need real work factors.
config :bcrypt_elixir, log_rounds: 4

# The go-live clock: tests call Articles.go_live_due/1 directly.
config :texttile, :start_scheduler, false

# The conversion queue would run ffmpeg under a sandbox owner of
# another test. Tests convert by hand, or start a queue of their own.
config :texttile, :start_video_queue, false
