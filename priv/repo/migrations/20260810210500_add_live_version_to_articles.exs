defmodule Texttile.Repo.Migrations.AddLiveVersionToArticles do
  use Ecto.Migration

  @moduledoc """
  The text the readers have. Until now a keystroke in a live entry was
  on the site the same second, so a half-finished sentence was
  published by typing it. From here the entry keeps two texts: the one
  in the editor, which is the working copy, and the one this column
  points at, which is what a reader gets.

  Only the title and the body split in two. Tags, the address, the
  tiles and the switches stay one thing and go live as they are
  changed, which is what a version has always held and what the editor
  has always promised.

  Every entry that is live at the upgrade gets a version of its text as
  it stands, and this column points at it: nothing a reader can see
  changes on the day of the upgrade. A draft has no reader and no row
  here.
  """

  def up do
    alter table(:articles) do
      add :live_version_id, references(:article_versions, on_delete: :nilify_all)
    end

    create index(:articles, [:live_version_id])

    # The text of every live entry, as a version of its own. `user_id`
    # is the author of the entry where the column above found one.
    execute """
    INSERT INTO article_versions (article_id, title, body, user_id, inserted_at)
    SELECT a.id, a.title, a.body, a.user_id, CURRENT_TIMESTAMP
      FROM articles a
     WHERE a.status = 'published'
    """

    execute """
    UPDATE articles
       SET live_version_id = (
         SELECT v.id
           FROM article_versions v
          WHERE v.article_id = articles.id
          ORDER BY v.id DESC
          LIMIT 1
       )
     WHERE status = 'published'
    """
  end

  def down do
    drop index(:articles, [:live_version_id])

    alter table(:articles) do
      remove :live_version_id
    end
  end
end
