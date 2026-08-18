# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :texttile,
  ecto_repos: [Texttile.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :texttile, TexttileWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TexttileWeb.ErrorHTML, json: TexttileWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Texttile.PubSub,
  live_view: [signing_salt: "icWZEdn+"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  texttile: [
    args:
      ~w(js/app.js --bundle --target=es2022 --format=esm --splitting --chunk-names=chunks/[name]-[hash] --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ],
  # The reader's script stays one self-contained file: a reader page
  # costs one request, not a module graph. It shares its sources with
  # the admin bundle at build time and nothing at load time.
  public: [
    args:
      ~w(js/public.js --bundle --target=es2022 --format=iife --outdir=../priv/static/assets/js),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  texttile: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Parameters that never belong in a log line or a crash report. Phoenix
# filters "password" on its own; the rest are ours to name.
config :phoenix, :filter_parameters, ["password", "token", "secret", "email"]

# Mail: the adapter is chosen at runtime via MAIL_ADAPTER (see runtime.exs).
# Without it, mails land in the local preview mailbox (/dev/mailbox).
config :texttile, Texttile.Mailer, adapter: Swoosh.Adapters.Local
config :swoosh, :api_client, Swoosh.ApiClient.Req
config :texttile, :mail_from, "texttile@localhost"

# Translations. English is the language of the source: every msgid is
# the English sentence itself, so English needs no catalogue of its own
# and an untranslated string reads as English. Each other language is
# one file, priv/gettext/<locale>/LC_MESSAGES/default.po.
config :texttile, TexttileWeb.Gettext, default_locale: "en"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
