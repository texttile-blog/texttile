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

  # A markdown image reference in the words as the writer left it, and
  # the two alt texts an upload writes while it has no address yet.
  # The editor hook writes all three, see `refs/1`.
  @source_reference ~r/!\[([^\]]*)\]\(([^)]*)\)/
  @uploading ~r/^Uploading (.+)…$/
  @failed ~r/^Upload failed: (.+)$/

  @uploads_prefix "/uploads/"

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

  ## The references in the words themselves

  @doc """
  The one reading of the words that the image panel, the gallery, the
  importer and the delete use.

  A markdown image reference in the words IS the picture or the film.
  While an upload is still running it holds its place with a token,
  `![Uploading name…]()`, and a failed one with a marker,
  `![Upload failed: name]()`. Those two shapes are written by the
  editor hook in `assets/js/body_ed_core.js` (upToken, failToken,
  doneRef) and read here. Nothing else states the shape, so the two
  ends have to be changed together.

  Answers them in reading order as
  `%{kind: :running | :failed | :done, file: name, raw: text, url: url}`.
  """
  def refs(body) do
    @source_reference
    |> Regex.scan(to_string(body))
    |> Enum.flat_map(fn [raw, alt, url] ->
      url = String.trim(url)

      cond do
        url != "" ->
          [%{kind: :done, file: url |> String.split("/") |> List.last(), raw: raw, url: url}]

        match = Regex.run(@uploading, alt) ->
          [%{kind: :running, file: Enum.at(match, 1), raw: raw, url: nil}]

        match = Regex.run(@failed, alt) ->
          [%{kind: :failed, file: Enum.at(match, 1), raw: raw, url: nil}]

        true ->
          []
      end
    end)
  end

  @doc """
  The files under the uploads root that these words own, once each and
  without the `#{@uploads_prefix}` in front of them: what a delete has
  to take with it, and what the gallery and the importer count as
  belonging to the text. A reference to somewhere else is nobody's file.
  """
  def upload_paths(body) do
    body
    |> upload_urls()
    |> Enum.flat_map(fn
      @uploads_prefix <> relative -> [relative]
      _elsewhere -> []
    end)
  end

  @doc "The addresses of the finished references, once each, as written."
  def upload_urls(body) do
    body
    |> refs()
    |> Enum.flat_map(fn
      %{kind: :done, url: url} -> [url]
      _unfinished -> []
    end)
    |> Enum.uniq()
  end

  @doc """
  Every reference in the words, handed to `draw` as
  `(whole, alt, url)`, with what comes out standing in its place.
  """
  def rewrite(body, draw) when is_function(draw, 3) do
    Regex.replace(@source_reference, to_string(body), draw)
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
