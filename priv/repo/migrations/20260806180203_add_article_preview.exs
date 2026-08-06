defmodule Texttile.Repo.Migrations.AddArticlePreview do
  use Ecto.Migration

  def change do
    alter table(:articles) do
      # The chosen preview image, as an uploads-relative path. Empty
      # means the first image of the text speaks for it.
      add :preview_path, :string
    end
  end
end
