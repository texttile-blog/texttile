defmodule Texttile.Repo.Migrations.StampTextsPublishedBeforeTheNewsletter do
  use Ecto.Migration

  # Every text that was already live when the newsletter arrived counts
  # as told about: its readers had it before there was a list. Without
  # the stamp the first Unpublish and Publish of an old text would mail
  # it to everybody as news.
  def up do
    execute """
    UPDATE articles
       SET notified_on = publish_date
     WHERE status = 'published'
       AND notified_on IS NULL
       AND publish_date IS NOT NULL
    """
  end

  def down do
    :ok
  end
end
