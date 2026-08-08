defmodule Texttile.StatsFixtures do
  @moduledoc """
  Counted views, written straight into the table.

  The way from a request to a row is under test in
  `Texttile.StatsTest` and `TexttileWeb.StatsBeaconTest`. Everywhere
  else the rows are the setup, not the subject, so they go in here
  without a browser line, a salt or a rate limit in the way.
  """

  alias Texttile.Repo
  alias Texttile.Stats

  @doc """
  Writes `count` views, each from a reader of their own.

  Takes `:day` (today), `:path` ("/x"), `:article_id` (none) and
  `:referrer_host` (none, which means the reader arrived direct).
  """
  def seed_views(count, opts \\ []) do
    day = Keyword.get(opts, :day, Date.utc_today())
    tag = System.unique_integer([:positive])

    for n <- 1..count do
      Repo.insert!(%Stats.View{
        day: day,
        path: Keyword.get(opts, :path, "/x"),
        article_id: Keyword.get(opts, :article_id),
        visitor: "seed-#{tag}-#{n}",
        referrer_host: Keyword.get(opts, :referrer_host),
        inserted_at: DateTime.new!(day, ~T[12:00:00], "Etc/UTC")
      })
    end
  end
end
