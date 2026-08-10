defmodule Texttile.Backup.Fingerprint do
  @moduledoc """
  What the installation knows about one file below the uploads root:
  where it lies, how big it is, when it was last written and its
  SHA-256.

  The hash is the whole point of the row. Reading a file to hash it
  costs as much as sending it, so it is taken once, when the file is
  first seen, and read from here ever after. Size and mtime are how
  the row knows it still describes the file on disk.
  """
  use Ecto.Schema

  schema "backup_fingerprints" do
    field :path, :string
    field :size, :integer
    field :mtime, :integer
    field :sha256, :string
  end
end
