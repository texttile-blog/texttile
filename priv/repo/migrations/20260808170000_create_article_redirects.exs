defmodule Texttile.Repo.Migrations.CreateArticleRedirects do
  use Ecto.Migration

  def change do
    # One row per address an entry used to live at. The address of a
    # post carries its publish date, so changing the date moves the
    # entry exactly as changing the slug does, and both leave a row
    # here. A reader who follows an old link is sent on.
    #
    # The rows go with the entry: a deleted entry has nowhere to send
    # anybody, and the address is free for the next text.
    create table(:article_redirects) do
      add :article_id, references(:articles, on_delete: :delete_all), null: false
      add :path, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:article_redirects, [:path])
    create index(:article_redirects, [:article_id])
  end
end
