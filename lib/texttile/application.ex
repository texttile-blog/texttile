defmodule Texttile.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # The first-run setup window is measured from this moment.
    Texttile.Boot.record_start()

    children = [
      TexttileWeb.Telemetry,
      Texttile.Repo,
      # Migrations run once, in the container CMD (bin/migrate), before the app
      # boots. No Ecto.Migrator child: a failing migration must fail the boot
      # step cleanly instead of crash-looping the supervision tree.
      {DNSCluster, query: Application.get_env(:texttile, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Texttile.PubSub},
      TexttileWeb.Presence,
      # Start a worker by calling: Texttile.Worker.start_link(arg)
      # {Texttile.Worker, arg},
      # Start to serve requests, typically the last entry
      TexttileWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Texttile.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TexttileWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
