defmodule Texttile.Repo.Migrations.DropProtectedFromArticles do
  use Ecto.Migration

  # The blog password guards the blog, never one text: a text has no
  # switch of its own any more.
  def change do
    alter table(:articles) do
      remove :protected, :boolean, default: false, null: false
    end
  end
end
