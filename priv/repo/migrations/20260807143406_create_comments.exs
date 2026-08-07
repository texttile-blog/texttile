defmodule Texttile.Repo.Migrations.CreateComments do
  use Ecto.Migration

  def change do
    # One row per address that ever commented. The token travels in the
    # confirmation mail; one link per address, for all its comments.
    create table(:comment_addresses) do
      add :email, :string, null: false
      add :token, :string, null: false
      add :confirmed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:comment_addresses, [:email])
    create unique_index(:comment_addresses, [:token])

    create table(:comments) do
      add :article_id, references(:articles, on_delete: :delete_all), null: false
      add :address_id, references(:comment_addresses, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :body, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:comments, [:article_id])
    create index(:comments, [:address_id])
  end
end
