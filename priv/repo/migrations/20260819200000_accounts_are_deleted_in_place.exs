defmodule Texttile.Repo.Migrations.AccountsAreDeletedInPlace do
  @moduledoc """
  A deleted account keeps its row and its name.

  What a person wrote belongs to the site, and the name under it is
  part of the entry: taking the row away took the byline of every entry
  with it, and the version list, the log and the comments of the admin
  area lost who had been there. The account is marked deleted instead.
  It cannot sign in, it is not in the list of accounts any more, and
  readers see nothing about it: the entries read exactly as before.

  The address is free again the moment the account is deleted, so the
  unique index only counts the accounts that are still there.
  """

  use Ecto.Migration

  def change do
    alter table(:users) do
      add :deleted_at, :utc_datetime
    end

    drop unique_index(:users, [:email])
    create unique_index(:users, [:email], where: "deleted_at IS NULL")
  end
end
