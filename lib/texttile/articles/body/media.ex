defmodule Texttile.Articles.Body.Media do
  @moduledoc """
  One reference to an uploaded file, as the body of an entry carries it.

    * `path` is the file under the uploads root, without the `/uploads/`
      in front of it.
    * `label` is what the writer put in the alt text, or the word that
      stands in for one.
    * `video?` says whether the file is a film.
    * `playback` is what `Texttile.Videos.playback/1` answers for a
      film ffmpeg is through with, and nil while it is not, or for a
      picture.

  `head` and `tail` are the rest of the tag the markdown renderer
  wrote, on either side of the address. Read them through `picture/2`,
  which keeps the tag together.
  """

  defstruct [:path, :label, :playback, :head, :tail, video?: false]

  @doc """
  The picture the writer wrote, pointing somewhere else. Everything
  else on the tag - the alt text, a title, a class - stands as it did.
  """
  def picture(%__MODULE__{} = media, src) do
    ~s(<img#{media.head}src="#{src}"#{String.trim_trailing(media.tail)} />)
  end
end
