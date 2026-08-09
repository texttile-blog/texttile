defmodule Texttile.Repo.Migrations.AddCommentWebsiteAndImportMark do
  use Ecto.Migration

  def change do
    alter table(:comments) do
      # The address the author gave for themselves, in the comment form
      # or in a bundle. The name over the comment links to it.
      add :website, :string

      # The comment came out of a bundle. Importing the same bundle
      # again removes what the last import wrote and writes it anew, so
      # a second run gives the same comments, not two of each. A
      # comment a reader wrote here has nothing here and stays.
      add :imported_at, :utc_datetime
    end
  end
end
