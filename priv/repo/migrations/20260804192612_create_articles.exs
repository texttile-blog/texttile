defmodule Texttile.Repo.Migrations.CreateArticles do
  use Ecto.Migration

  def change do
    create table(:articles) do
      add :title, :string, null: false, default: ""
      add :body, :text, null: false, default: ""
      add :slug, :string
      add :status, :string, null: false, default: "draft"
      add :publish_date, :date
      add :type, :string, null: false, default: "post"
      add :tags, :string, null: false, default: ""
      add :allow_comments, :boolean, null: false, default: true
      add :notify_on_publish, :boolean, null: false, default: true
      add :notified_on, :date

      timestamps(type: :utc_datetime)
    end

    create unique_index(:articles, [:slug], where: "slug IS NOT NULL")

    create table(:article_versions) do
      add :article_id, references(:articles, on_delete: :delete_all), null: false
      add :title, :string, null: false, default: ""
      add :body, :text, null: false, default: ""
      add :user_id, references(:users, on_delete: :nilify_all)

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:article_versions, [:article_id])

    create table(:article_log) do
      add :article_id, references(:articles, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :nilify_all)
      add :text, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:article_log, [:article_id])
  end
end
