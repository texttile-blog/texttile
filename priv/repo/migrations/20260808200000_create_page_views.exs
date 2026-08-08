defmodule Texttile.Repo.Migrations.CreatePageViews do
  use Ecto.Migration

  def change do
    # One row per counted view. Nothing here names a person: the
    # visitor is a hash of the day's salt, and that salt is gone by
    # tomorrow. A deleted entry leaves its views behind as plain
    # addresses, so the total of the blog stays the total.
    create table(:page_views) do
      add :day, :date, null: false
      add :path, :string, null: false
      add :article_id, references(:articles, on_delete: :nilify_all)
      add :visitor, :string, null: false
      add :referrer_host, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:page_views, [:day])
    create index(:page_views, [:article_id])
    # The repeat check reads by visitor and address, newest first.
    create index(:page_views, [:visitor, :path])
  end
end
