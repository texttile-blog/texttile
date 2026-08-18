defmodule Texttile.Repo.Migrations.HashSessionTokens do
  @moduledoc """
  The sessions table keeps the hash of a token instead of the token, the
  way the login links already do.

  The rows that are there are converted, not thrown away: the hash of a
  token is made from the token, so every browser that is signed in now
  stays signed in. Backwards it does not go: a hash gives no token back,
  so a downgrade signs everybody out. That is the point of the column.
  """

  use Ecto.Migration

  import Ecto.Query

  def up do
    drop unique_index(:sessions, [:token])
    rename table(:sessions), :token, to: :token_hash

    flush()

    from(s in "sessions", select: {s.id, s.token_hash})
    |> Texttile.Repo.all()
    |> Enum.each(fn {id, token} ->
      hash = :crypto.hash(:sha256, token)

      from(s in "sessions", where: s.id == ^id)
      |> Texttile.Repo.update_all(set: [token_hash: hash])
    end)

    create unique_index(:sessions, [:token_hash])
  end

  def down do
    # A token cannot be read back out of its hash, so the sessions that
    # exist cannot travel back. They go, and their browsers sign in
    # again.
    Texttile.Repo.delete_all(from(s in "sessions"))

    drop unique_index(:sessions, [:token_hash])
    rename table(:sessions), :token_hash, to: :token
    create unique_index(:sessions, [:token])
  end
end
