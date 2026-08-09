defmodule Texttile.Articles.Visibility do
  @moduledoc """
  Who may read an entry.

  One question, asked in a lot of places: the reader page, the tag
  archive, the feed, the neighbours under a text, the comment form, the
  view counter and the editor's own door to the public site. It used to
  be answered by writing `status == "published"` again wherever it came
  up, so a new entry state had to be found in nine modules before it
  was right. It is answered here now.

  Everything here is about the entry alone: is it live, does it take a
  comment, which entries are live. Two questions stay outside on
  purpose.

  Whether somebody signed in may read an entry that is not live is not
  one question but two queries, because the reader's address and the
  admin's are looked up differently. `TexttileWeb.SiteController` asks
  both, side by side, where the session is.

  The site password is not about an entry at all: it guards the blog or
  nothing, no entry carries a switch of its own, and it is answered on
  the way in by `TexttileWeb.SiteGate`.
  """

  import Ecto.Query, warn: false

  alias Texttile.Articles.Article

  @live "published"

  @doc """
  The status an entry wears while it is live. The one place the word
  itself is written.
  """
  def live_status, do: @live

  @doc "Is the entry on the site?"
  def live?(%Article{status: @live}), do: true
  def live?(%Article{}), do: false
  def live?(nil), do: false

  @doc """
  Does the entry take a comment? An entry that is not live takes none,
  however its own switch stands: the reader who could write one cannot
  reach the page at all, and the form would post to an address that
  answers nothing.
  """
  def open_for_comments?(%Article{allow_comments: true} = article), do: live?(article)
  def open_for_comments?(_article), do: false

  @doc "The same question as a query: the live entries out of `query`."
  def live(query \\ Article), do: where(query, [a], a.status == ^@live)
end
