defmodule Texttile.Repo.Migrations.AddGalleryDescriptions do
  use Ecto.Migration

  def change do
    alter table(:gallery_images) do
      add :description, :text, null: false, default: ""
    end
  end
end
