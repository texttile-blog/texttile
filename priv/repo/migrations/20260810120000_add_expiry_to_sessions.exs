defmodule Texttile.Repo.Migrations.AddExpiryToSessions do
  use Ecto.Migration

  @moduledoc """
  A session carries the day it ends. Until now every session lived
  sixty days from the same rule, and the cookie behind it died with the
  browser; now the sign-in decides, two days or fourteen, and the row
  says which. The sessions that are open at the upgrade keep the longer
  span from the moment they were opened.
  """

  def up do
    alter table(:sessions) do
      add :expires_at, :utc_datetime
    end

    # The shape the app reads and writes: SQLite keeps a moment as text,
    # and the adapter's text is ISO 8601. SQLite's own datetime() writes
    # a space where that has a T, and every comparison here is a
    # comparison of strings, so a row in the other shape would read as
    # expired up to a day early.
    execute "UPDATE sessions SET expires_at = strftime('%Y-%m-%dT%H:%M:%SZ', inserted_at, '+14 days')"

    create index(:sessions, [:expires_at])
  end

  def down do
    drop index(:sessions, [:expires_at])

    alter table(:sessions) do
      remove :expires_at
    end
  end
end
