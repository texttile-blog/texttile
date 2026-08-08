defmodule Texttile.Markdown do
  @moduledoc """
  Markdown to HTML, the one way the whole app renders it: the about
  block now, the texts later. Raw HTML in the source is shown as text,
  never executed; markdown is the writing surface, not HTML.
  """

  @doc "Renders markdown as an HTML string."
  def to_html(markdown) when is_binary(markdown) do
    MDEx.to_html!(markdown,
      extension: [strikethrough: true, table: true, autolink: true],
      render: [escape: true]
    )
  end

  @doc """
  The alt text of a rendered `<img>` tag, and a word to stand in for it
  when the reference carries none. Whoever turns such a tag into
  something else - a player, a link in a feed - needs the same reading.
  """
  def alt_of(tag) do
    case Regex.run(~r/alt="([^"]*)"/, tag) do
      [_whole, ""] -> "Video"
      [_whole, alt] -> alt
      nil -> "Video"
    end
  end
end
