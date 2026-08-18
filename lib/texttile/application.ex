defmodule Texttile.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TexttileWeb.Telemetry,
      Texttile.Repo,
      # Migrations run once, in the container CMD (bin/migrate), before the app
      # boots. No Ecto.Migrator child: a failing migration must fail the boot
      # step cleanly instead of crash-looping the supervision tree.
      {DNSCluster, query: Application.get_env(:texttile, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Texttile.PubSub},
      TexttileWeb.Presence,
      # The soft document lock: one process per open article, under a
      # registry and a supervisor of their own.
      {Registry, keys: :unique, name: Texttile.Articles.Lock.registry()},
      {DynamicSupervisor, strategy: :one_for_one, name: Texttile.Articles.Lock.supervisor()},
      # The bundle import: one job at a time, its work in watched tasks.
      {Task.Supervisor, name: Texttile.Import.TaskSupervisor},
      Texttile.Import.Job,
      # The subscriber mails leave here, so a publish click never waits
      # for another server.
      {Task.Supervisor, name: Texttile.Newsletter.TaskSupervisor},
      # And the mail about a new comment, for the same reason: the
      # reader who wrote it waits for this server, not for another one.
      {Task.Supervisor, name: Texttile.Comments.TaskSupervisor},
      # ffmpeg runs under this one, one conversion at a time.
      {Task.Supervisor, name: Texttile.Videos.TaskSupervisor},
      # The invisible spam filter of the public forms: a few knocks
      # per caller per minute.
      Texttile.RateLimiter,
      # The same filter in front of the view counter, wider: a reader
      # turns pages faster than they write comments.
      {Texttile.RateLimiter,
       name: Texttile.Stats.limiter(), limit: Texttile.Stats.limiter_per_minute()},
      # And in front of the backup endpoints, wider still: a client
      # fetching a thousand pictures is doing its job.
      {Texttile.RateLimiter,
       name: Texttile.Backup.limiter(), limit: Texttile.Backup.limiter_per_minute()},
      # And in front of the password doors, narrow: a person types a
      # password a few times a minute, a machine types thousands.
      {Texttile.RateLimiter,
       name: Texttile.Accounts.door_limiter(), limit: Texttile.Accounts.door_limiter_per_minute()},
      # The secret behind every visitor number, held here and nowhere
      # else, thrown away when the day turns.
      Texttile.Stats.Salt,
      # Start to serve requests, typically the last entry
      TexttileWeb.Endpoint
    ]

    # The go-live clock and the two sweepers stay out of tests: they
    # would race the SQL sandbox. The tests call go_live_due/1,
    # Gallery.sweep_due/0 and Comments.sweep_due/0 directly instead.
    children =
      if Application.get_env(:texttile, :start_scheduler, true) do
        children ++
          [Texttile.Articles.Scheduler, Texttile.Gallery.Sweeper, Texttile.Comments.Sweeper]
      else
        children
      end

    # The video queue stays out of tests for the same reason. A test
    # that wants a conversion converts by hand, or starts a queue of
    # its own under its own sandbox owner.
    children =
      if Application.get_env(:texttile, :start_video_queue, true) do
        children ++ [Texttile.Videos.Queue]
      else
        children
      end

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
