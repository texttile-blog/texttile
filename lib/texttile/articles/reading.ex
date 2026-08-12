defmodule Texttile.Articles.Reading do
  @moduledoc """
  Which of an entry's two texts an audience gets.

  A live entry keeps two texts: the working copy in the editor, and the
  version `live_version_id` points at. `Visibility` answers whether an
  entry may be read at all; this module answers the second half of the
  rule, which text the one who reads it gets. Every path that hands an
  entry out names its audience here, so the choice is made in one place
  and a new reader path cannot quietly hand out the working copy.

  `:reader` is anybody who is not signed in: they get the published
  text, through `Articles.as_read/1`, and nothing that is not live.
  `:admin` is whoever is signed in: they get the working copy, and
  `pending?/2` says whether the strip over the text is owed that tells
  them so.
  """

  import Ecto.Query

  alias Texttile.Articles
  alias Texttile.Articles.Article
  alias Texttile.Articles.Visibility
  alias Texttile.Repo

  @type audience :: :reader | :admin

  @doc "The audience a signed-in state makes: an admin, or a reader."
  def audience(nil), do: :reader
  def audience(_signed_in), do: :admin

  @doc """
  The entry, or the list of entries, as this audience gets it. A
  reader gets the published text; an admin gets the working copy, so
  the way out of the editor shows what is being written and not what
  the site said yesterday.
  """
  def text(articles, audience) when is_list(articles),
    do: Enum.map(articles, &text(&1, audience))

  def text(%Article{} = article, :reader), do: Articles.as_read(article)
  def text(%Article{} = article, :admin), do: article

  @doc """
  Whether the strip over the entry is owed: only an admin gets one, and
  only while the working copy says something the readers have not been
  given yet.
  """
  def pending?(%Article{} = article, :admin), do: Articles.unpublished_changes?(article)
  def pending?(%Article{}, :reader), do: false

  @doc """
  The post this audience may open at a date and a slug, or nil. The
  date is part of the address: another day is another address, and it
  holds no text.

  A reader only finds a post that is live. An admin also finds one
  that is not live yet at the address it will wear, so the editor's
  way out leads into the real site instead of a second design of it; a
  post with no day yet borrows today, exactly as `Articles.public_prefix/1`
  does, so the address the editor prints is the address that answers.
  """
  def post(%Date{} = date, slug, :reader) when is_binary(slug) do
    live_query("post")
    |> where([a], a.slug == ^slug and a.publish_date == ^date)
    |> Repo.one()
  end

  def post(%Date{} = date, slug, :admin) when is_binary(slug) do
    post(date, slug, :reader) || any_post(date, slug) || dateless_post(date, slug)
  end

  @doc """
  The page this audience may open behind a short address, or nil. A
  reader only finds a live page; an admin also finds one that is not
  live yet.
  """
  def page(slug, :reader) when is_binary(slug) do
    live_query("page") |> where([a], a.slug == ^slug) |> Repo.one()
  end

  def page(slug, :admin) when is_binary(slug) do
    page(slug, :reader) ||
      Repo.one(from a in any_query("page"), where: a.slug == ^slug)
  end

  defp any_post(date, slug) do
    Repo.one(
      from a in any_query("post"),
        where: a.slug == ^slug and a.publish_date == ^date
    )
  end

  defp dateless_post(date, slug) do
    if Date.compare(date, Date.utc_today()) == :eq do
      Repo.one(
        from a in any_query("post"),
          where: a.slug == ^slug and is_nil(a.publish_date)
      )
    end
  end

  # Every reader query carries the author, who stands beside the day,
  # and the published version, which is the text itself. Loading them
  # here means no reader page can forget either.
  defp live_query(type) do
    Visibility.live() |> where([a], a.type == ^type) |> preload([:user, :live_version])
  end

  defp any_query(type) do
    from a in Article, where: a.type == ^type, preload: [:user, :live_version]
  end
end
