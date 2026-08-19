defmodule Texttile.Repo.Migrations.EmailIsTheIdentity do
  @moduledoc """
  The email address becomes the identity of an account, and the username
  goes.

  An account carried three names for one person: the username it signed
  in with, the displayed name readers see, and the address mail goes to.
  Two of them ended up under the entries. What is left says one thing
  each: the address is who you are, the displayed name is what readers
  see.

  The username is not thrown away. It becomes the displayed name of
  every account that has none, so the bylines of the blog read the same
  after this migration as before it.
  """

  use Ecto.Migration

  def up do
    # The name readers see, for an account that never set one.
    execute """
    UPDATE users SET display_name = username
    WHERE display_name IS NULL OR trim(display_name) = ''
    """

    # SQLite refuses to drop a column an index carries.
    drop unique_index(:users, [:username])
    execute "ALTER TABLE users DROP COLUMN username"
  end

  def down do
    # The usernames are gone, so they are made again out of the
    # addresses: the part in front of the @, with the id appended where
    # two addresses share one. The column comes back without its NOT
    # NULL, which SQLite cannot add to a table that stands.
    execute "ALTER TABLE users ADD COLUMN username TEXT"

    execute """
    UPDATE users SET username = lower(substr(email, 1, instr(email, '@') - 1))
    """

    execute """
    UPDATE users SET username = username || '-' || id
    WHERE id NOT IN (SELECT min(id) FROM users GROUP BY username)
    """

    create unique_index(:users, [:username])
  end
end
