defmodule Texttile.MixProject do
  use Mix.Project

  def project do
    [
      app: :texttile,
      version: version(),
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # The version of a build is the Git tag the publish workflow sets on
  # the merge commit, handed in as TEXTTILE_VERSION. No pull request
  # raises it. A development machine and the test suite run as 0.0.0.
  defp version, do: System.get_env("TEXTTILE_VERSION", "0.0.0")

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Texttile.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.7"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:swoosh, "~> 1.27"},
      {:vix, "~> 0.35"},
      {:mdex, "~> 0.9"},
      {:bcrypt_elixir, "~> 3.0"},
      {:req, "~> 0.7"},
      {:gen_smtp, "~> 1.3"},
      {:phoenix_test, "~> 0.11.1", only: :test, runtime: false},
      {:phoenix_test_playwright, "~> 0.15.0", only: :test, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      # Assets are built so browser e2e tests load real CSS/JS (LiveView needs app.js).
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "assets.build", "test"],
      "assets.setup": [
        "tailwind.install --if-missing",
        &sign_tailwind/1,
        "esbuild.install --if-missing"
      ],
      # The setup runs first, so a fresh worktree never runs an unsigned Tailwind.
      "assets.build": [
        "compile",
        "assets.setup",
        "tailwind texttile",
        "esbuild texttile",
        "esbuild public"
      ],
      "assets.deploy": [
        "tailwind texttile --minify",
        "esbuild texttile --minify",
        "esbuild public --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        # A sentence nobody extracted is a sentence nobody can translate.
        "gettext.extract --check-up-to-date",
        "test"
      ]
    ]
  end

  # The macOS Tailwind binary ships with a broken signature, and macOS kills it
  # at start (exit 137). An ad hoc signature on this machine repairs it.
  defp sign_tailwind(_args) do
    with {:unix, :darwin} <- :os.type(),
         path = Tailwind.bin_path(),
         {_, status} when status != 0 <-
           System.cmd("codesign", ["--verify", path], stderr_to_stdout: true),
         {output, status} when status != 0 <-
           System.cmd("codesign", ["--force", "--sign", "-", path], stderr_to_stdout: true) do
      Mix.raise("Could not sign #{path}: #{output}")
    end
  end
end
