defmodule Texttile.Repo.Migrations.AccountsFromTheConfiguration do
  use Ecto.Migration

  def up do
    # An account is created at its first sign-in, from a username in the
    # configuration. There is nobody to ask for an email address at that
    # moment, so the column becomes optional and the profile fills it in
    # later. SQLite cannot modify a column, so the column is replaced
    # around a copy, and its index has to step aside for that.
    drop unique_index(:users, [:email])
    execute "ALTER TABLE users ADD COLUMN email_tmp TEXT"
    execute "UPDATE users SET email_tmp = email"
    execute "ALTER TABLE users DROP COLUMN email"
    execute "ALTER TABLE users ADD COLUMN email TEXT"
    execute "UPDATE users SET email = email_tmp"
    execute "ALTER TABLE users DROP COLUMN email_tmp"
    create unique_index(:users, [:email])
  end

  def down do
    # Accounts without an address cannot go back into a NOT NULL column.
    # Give them one in the application before rolling back.
    drop unique_index(:users, [:email])
    execute "ALTER TABLE users ADD COLUMN email_tmp TEXT"
    execute "UPDATE users SET email_tmp = email"
    execute "ALTER TABLE users DROP COLUMN email"
    execute "ALTER TABLE users ADD COLUMN email TEXT NOT NULL DEFAULT ''"
    execute "UPDATE users SET email = email_tmp"
    execute "ALTER TABLE users DROP COLUMN email_tmp"
    create unique_index(:users, [:email])
  end
end
