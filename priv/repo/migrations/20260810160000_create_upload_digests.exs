defmodule Texttile.Repo.Migrations.CreateUploadDigests do
  use Ecto.Migration

  @moduledoc """
  What a stored picture is made of, so an entry can take each picture
  once. One row per file below `images/`: the path, and the SHA-256 of
  its bytes. The row is written when the file is stored and goes when
  the file goes.

  The pictures that were on disk before the upgrade carry no row. They
  get one the first time the entry that holds them takes an upload, so
  nothing has to walk the whole volume at boot.
  """

  def change do
    create table(:upload_digests) do
      add :path, :string, null: false
      add :digest, :string, null: false
    end

    create unique_index(:upload_digests, [:path])
    create index(:upload_digests, [:digest])
  end
end
