defmodule Texttile.Repo.Migrations.CreateUploadDigests do
  use Ecto.Migration

  @moduledoc """
  What a stored picture is made of, so an entry can take each picture
  once. One row per file below `images/`: the path, and the SHA-256 of
  its bytes. The row is written when the file is stored and goes when
  the file goes.

  `article_id` is the entry the picture came in through, where it came
  in through one. A picture pasted into a text is stored before the
  text says a word about it, so without this a second paste of the
  same picture would find nothing to compare itself with.

  The pictures that were on disk before the upgrade carry no row. They
  get one the first time the entry that holds them takes an upload, so
  nothing has to walk the whole volume at boot.
  """

  def change do
    create table(:upload_digests) do
      add :path, :string, null: false
      add :digest, :string, null: false
      add :article_id, references(:articles, on_delete: :nilify_all)
    end

    create unique_index(:upload_digests, [:path])
    create index(:upload_digests, [:digest])
    create index(:upload_digests, [:article_id])
  end
end
