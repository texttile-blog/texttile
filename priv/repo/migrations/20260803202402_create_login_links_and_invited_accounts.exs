defmodule Texttile.Repo.Migrations.CreateLoginLinksAndInvitedAccounts do
  use Ecto.Migration

  def up do
    create table(:login_links) do
      add :token_hash, :binary, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:login_links, [:token_hash])
    create index(:login_links, [:user_id])

    # An invited account has no password until its owner sets one, so the
    # NOT NULL on password_hash has to go. SQLite cannot modify a column;
    # recreate it around a copy instead.
    execute "ALTER TABLE users ADD COLUMN password_hash_tmp TEXT"
    execute "UPDATE users SET password_hash_tmp = password_hash"
    execute "ALTER TABLE users DROP COLUMN password_hash"
    execute "ALTER TABLE users ADD COLUMN password_hash TEXT"
    execute "UPDATE users SET password_hash = password_hash_tmp"
    execute "ALTER TABLE users DROP COLUMN password_hash_tmp"
  end

  def down do
    drop table(:login_links)
  end
end
