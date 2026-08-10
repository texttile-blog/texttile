defmodule Texttile.Uploads.Digest do
  @moduledoc """
  What one stored picture is made of: its path below the uploads root
  and the SHA-256 of its bytes. Two files with the same digest are the
  same picture, whatever they are called.

  The row is written when the picture is stored and goes when the
  picture goes, so nothing here outlives a file.
  """
  use Ecto.Schema

  schema "upload_digests" do
    field :path, :string
    field :digest, :string
  end
end
