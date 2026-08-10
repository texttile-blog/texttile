defmodule Texttile.Uploads.Digest do
  @moduledoc """
  What one stored picture is made of: its path below the uploads root
  and the SHA-256 of its bytes. Two files with the same digest are the
  same picture, whatever they are called.

  The row is written when the picture is stored and goes when the
  picture goes, so nothing here outlives a file.

  `article_id` is the entry the picture came in through. A picture
  pasted into a text is stored before the text says a word about it,
  and this is what a second paste of the same picture, still in the
  air, is compared with.
  """
  use Ecto.Schema

  schema "upload_digests" do
    field :path, :string
    field :digest, :string
    field :article_id, :id
  end
end
