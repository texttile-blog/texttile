defmodule Texttile.Repo.Migrations.AddAuthorToArticles do
  use Ecto.Migration

  @moduledoc """
  Who started the entry. The overviews and the reader's page name them
  beside the day, so the name has to be one column away, not one query
  per row away.

  The entries that were here before the upgrade carry the name in
  their Log: the first line of every entry is "started the entry", and
  whoever wrote it is the author. So the backfill reads the oldest Log
  line of each entry. An entry whose Log was cut, or whose author has
  since left, keeps a nil here and is shown without a name.
  """

  def up do
    alter table(:articles) do
      add :user_id, references(:users, on_delete: :nilify_all)
    end

    create index(:articles, [:user_id])

    execute """
    UPDATE articles
       SET user_id = (
         SELECT l.user_id
           FROM article_log l
          WHERE l.article_id = articles.id
            AND l.user_id IS NOT NULL
          ORDER BY l.id ASC
          LIMIT 1
       )
    """
  end

  def down do
    drop index(:articles, [:user_id])

    alter table(:articles) do
      remove :user_id
    end
  end
end
