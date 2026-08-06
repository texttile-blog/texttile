defmodule Texttile.Repo.Migrations.AddProtectedToArticles do
  use Ecto.Migration

  def change do
    alter table(:articles) do
      # The per-text switch of the site password: this text lies behind
      # it. The password itself is one site setting, never per text.
      add :protected, :boolean, default: false, null: false
    end
  end
end
