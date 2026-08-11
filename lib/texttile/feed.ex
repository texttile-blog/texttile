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
  alias Texttile.Articles.Body
  alias Texttile.Articles.Body.Media
  alias Texttile.Articles.Reading
  alias Texttile.Images
  alias Texttile.Settings

  # Every address in a text that starts at the root of the site. The
  # media are absolute already when this runs, so it leaves them.
  @address ~r{\b(href|src)="/(?!/)([^"]*)"}

  @doc "The one address of the feed."
  def path, do: "/feed.xml"

  @doc "Whether the blog offers a feed: it does while no password guards it."
  def public?, do: not Settings.guarded?()

  @doc """
  The RSS 2.0 document, every published post inside it, newest first.

  `base` is the site's own address without a trailing slash. Every
  address in the feed grows out of it: a feed is read away from the
  site, where a path that starts with a slash leads nowhere.
  """
  def rss(base) do
    # A text without a slug, or a post without a day, has no address a
    # reader could follow. The site draws it as a card without a link;
    # the feed, which is nothing but addresses, leaves it out.
    #
    # The feed is a reader, and it is the one reader whose copy cannot
    # be taken back once it is out.
    posts =
      Articles.list_published()
      |> Reading.text(:reader)
      |> Enum.filter(&Articles.public_path/1)

    channel = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:atom="http://www.w3.org/2005/Atom">
      <channel>
        <title>#{escape(Settings.site_title())}</title>
        <link>#{escape(base)}/</link>
        <description>#{escape(Settings.get(:site_description))}</description>
        <language>#{escape(Texttile.I18n.site_locale())}</language>
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
    |> Body.to_html(&draw_media(&1, base))
    |> absolute(base)
  end

  # A picture takes the reading size the site itself shows, never the
  # untouched original: a feed lands in mail readers and on slow lines.
  defp draw_media(%Media{video?: false} = media, base) do
    Media.picture(media, reading_size(media.path, base))
  end

  # No feed reader plays a film, and a rendition of one is nothing at
  # all. It goes as its poster with the way to the film behind it, and
  # while ffmpeg is not through, as the plain link it can always be.
  defp draw_media(%Media{playback: nil} = media, base) do
    ~s(<a href="#{base}/uploads/#{media.path}">#{media.label}</a>)
  end

  defp draw_media(%Media{playback: play} = media, base) do
    ~s(<a href="#{base}/uploads/#{play.mp4}">) <>
      ~s(<img src="#{reading_size(play.poster, base)}" alt="#{media.label}" />) <>
      ~s(</a>)
  end

  defp reading_size(path, base), do: "#{base}/renditions/#{Images.reading_edge()}/#{path}"

  # Every address the text carries, made absolute. The media are
  # absolute already, so this leaves them where they are.
  defp absolute(html, base) do
    Regex.replace(@address, html, fn _whole, attribute, rest ->
      attribute <> "=\"" <> base <> "/" <> rest <> "\""
    end)
  end

  # Everything on its way into the document goes through here, the
  # whole text of a post included: inside content:encoded its HTML is
  # text like any other.
  defp escape(text) do
    text
    |> to_string()
    |> scrub()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end

  # A control character is illegal in XML, and one of them makes the
  # whole document unreadable, not just its own text. They arrive by
  # paste from a PDF or a word processor. Tab, newline and return are
  # the three that XML allows and a text needs.
  @illegal ~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/

  defp scrub(text), do: String.replace(text, @illegal, "")
end
