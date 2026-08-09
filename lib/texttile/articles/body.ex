defmodule Texttile.Articles.Body do
  @moduledoc """
  The written text of an entry as HTML, with every reference to an
  uploaded file handed to whoever draws it.

  The markdown renderer writes `<img src="/uploads/...">` for a picture
  and for a film alike, and nothing else around it, so one pass over
  those tags finds all the media a text carries. What each one becomes
  is not the same everywhere: the reader page draws a player and a
  lightbox link, the feed draws a poster with the film behind it and
  absolute addresses throughout. Both used to walk the text themselves,
  with a regular expression each and the reading edge written twice.

  The walk lives here. The caller passes a function, gets one
  `Texttile.Articles.Body.Media` per reference, and answers with the
  HTML that goes in its place.
  """

  alias Texttile.Articles.Body.Media
  alias Texttile.Markdown
  alias Texttile.Videos

  # A whole <img> tag pointing into the uploads, in three pieces: what
  # stood before the address, the address, and what stood after it.
  @reference ~r{<img([^>]*?)src="/uploads/([^"]+)"([^>]*?)/?>}

  @doc """
  The body as HTML. `draw` is called once per reference to an uploaded
  file, with a `Media`, and answers the HTML that stands in its place.
  """
  def to_html(body, draw) when is_binary(body) and is_function(draw, 1) do
    html = Markdown.to_html(body)

    Regex.replace(@reference, html, fn whole, head, path, tail ->
      draw.(media(whole, head, path, tail))
    end)
  end

  defp media(whole, head, path, tail) do
    video? = Videos.video?(path)

    %Media{
      path: path,
      label: Markdown.alt_of(whole),
      video?: video?,
      playback: if(video?, do: Videos.playback(path)),
      head: head,
      tail: tail
    }
  end
end
