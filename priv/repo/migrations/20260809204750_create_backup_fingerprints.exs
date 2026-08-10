defmodule Texttile.Repo.Migrations.CreateBackupFingerprints do
  use Ecto.Migration

  def change do
    # One row per file below the uploads root, cache excluded: how big
    # it is, when it was last written, and its SHA-256. The hash is the
    # expensive part, so it is taken once and read from here after
    # that. Size and mtime say whether the file on disk is still the
    # one the hash was taken of.
    create table(:backup_fingerprints) do
      add :path, :string, null: false
      add :size, :integer, null: false
      add :mtime, :integer, null: false
      add :sha256, :string, null: false
    end

    create unique_index(:backup_fingerprints, [:path])
  end
end
