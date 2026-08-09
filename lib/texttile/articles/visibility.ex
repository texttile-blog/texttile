defmodule Texttile.Articles.Visibility do
  @moduledoc """
  Who may read an entry.

  One question, asked in a lot of places: the reader page, the tag
  archive, the feed, the neighbours under a text, the comment form, the
  view counter and the editor's own door to the public site. It used to
  be answered by writing `status == "published"` again wherever it came
  up, so a new entry state had to be found in nine modules before it
  was right. It is answered here now.

  Two words to keep apart:

    * **live** is about the entry: it is on the site, and its address
      answers for everybody.
    * **visible** is about a reader and an entry together: a reader
      sees what is live, and somebody signed in sees an entry whatever
      state it is in, because an entry wears its address from the
      moment it has a slug and the editor's way out leads into the
      real site.

  The site password is a third question and not this module's: it
  guards the blog or nothing, no entry carries a switch of its own, and
  it is answered on the way in by `TexttileWeb.SiteGate`.
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
  May this reader see the entry? `reader` is the signed-in account, or
  nil for everybody else.
  """
  def visible?(article, reader)
  def visible?(nil, _reader), do: false
  def visible?(%Article{} = article, nil), do: live?(article)
  def visible?(%Article{}, _reader), do: true

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
