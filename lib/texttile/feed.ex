defmodule Texttile.Feed do
  @moduledoc """
  The blog as an RSS feed: every published post with its whole text.

  A feed travels without a session. Nothing in it can ask for the site
  password, and a reader's feed reader would carry the texts on to
  anybody. So the answer to a guarded blog is not a thinner feed but
  none at all: while a password stands in front of the blog there is no
  feed, and no page offers one.
  """

  alias Texttile.Articles
  alias Texttile.Markdown
  alias Texttile.Settings

  # The pictures inside a text, and every other address that starts at
  # the root of the site.
  @picture ~r{(<img[^>]*?\bsrc=")/uploads/([^"]+)"}
  @address ~r{\b(href|src)="/(?!/)([^"]*)"}

  @doc "The one address of the feed."
  def path, do: "/feed.xml"

  @doc """
  Whether the blog offers a feed. It does while nothing is guarded: an
  open blog, or a protected one with a blank password, which is what
  the gate lets through as well.
  """
  def public? do
    Settings.get(:site_visibility) != "protected" or Settings.get(:site_password) == ""
  end

  @doc """
  The RSS 2.0 document, every published post inside it, newest first.

  `base` is the site's own address without a trailing slash. Every
  address in the feed grows out of it: a feed is read away from the
  site, where a path that starts with a slash leads nowhere.
  """
  def rss(base) do
    posts = Articles.list_published()

    channel = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:atom="http://www.w3.org/2005/Atom">
      <channel>
        <title>#{escape(Settings.site_title())}</title>
        <link>#{escape(base)}/</link>
        <description>#{escape(Settings.get(:site_description))}</description>
        <language>#{escape(Settings.get(:language))}</language>
        <atom:link href="#{escape(base <> path())}" rel="self" type="application/rss+xml"/>
    #{build_date(posts)}\
    """

    IO.iodata_to_binary([channel, Enum.map(posts, &item(&1, base)), "  </channel>\n</rss>\n"])
  end

  # When the newest text went live: the moment the feed last changed.
  defp build_date([%{publish_date: %Date{} = date} | _]),
    do: "    <lastBuildDate>#{stamp(date)}</lastBuildDate>\n"

  defp build_date(_posts), do: ""

  defp item(article, base) do
    link = escape(base <> Articles.public_path(article))

    """
        <item>
          <title>#{escape(Articles.display_title(article))}</title>
          <link>#{link}</link>
          <guid isPermaLink="true">#{link}</guid>
          <pubDate>#{stamp(article.publish_date)}</pubDate>
    #{categories(article)}\
          <description>#{escape(Articles.lead(article))}</description>
          <content:encoded>#{escape(body_html(article, base))}</content:encoded>
        </item>
    """
  end

  defp categories(article) do
    article
    |> Articles.tag_list()
    |> Enum.map_join(&"      <category>#{escape(&1)}</category>\n")
  end

  # A day, not a moment: a text goes live on a date, and the feed says
  # so the way RSS writes one.
  defp stamp(%Date{} = date), do: Calendar.strftime(date, "%a, %d %b %Y 00:00:00 +0000")

  defp body_html(article, base) do
    article.body
    |> Markdown.to_html()
    |> absolute(base)
  end

  # Every address the text carries, made absolute. Pictures take the
  # reading size the site itself shows, never the untouched original:
  # a feed lands in mail readers and on slow lines.
  defp absolute(html, base) do
    html =
      Regex.replace(@picture, html, fn _whole, head, file ->
        head <> base <> "/renditions/1320/" <> file <> "\""
      end)

    Regex.replace(@address, html, fn _whole, attribute, rest ->
      attribute <> "=\"" <> base <> "/" <> rest <> "\""
    end)
  end

  defp escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
