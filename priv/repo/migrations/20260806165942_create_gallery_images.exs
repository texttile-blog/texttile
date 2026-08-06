defmodule Texttile.Repo.Migrations.CreateGalleryImages do
  use Ecto.Migration

  def change do
    create table(:gallery_images) do
      add :article_id, references(:articles, on_delete: :delete_all), null: false
      add :path, :string, null: false
      add :filename, :string, null: false
      add :gallery_date, :utc_datetime_usec, null: false
      add :width, :integer
      add :height, :integer
      add :delete_after, :utc_datetime_usec

      timestamps(type: :utc_datetime)
    end

    create index(:gallery_images, [:article_id, :gallery_date])
    create index(:gallery_images, [:delete_after])
  end
end
