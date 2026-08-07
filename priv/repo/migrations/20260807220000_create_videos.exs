defmodule Texttile.Repo.Migrations.CreateVideos do
  use Ecto.Migration

  def change do
    # One row per uploaded video, found by the path of the original.
    # The original is kept as it came; this row names what ffmpeg made
    # from it and how far the conversion has got.
    create table(:videos) do
      add :path, :string, null: false
      add :mp4_path, :string
      add :poster_path, :string
      add :width, :integer
      add :height, :integer
      add :duration_ms, :integer
      add :state, :string, null: false, default: "queued"
      add :error, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:videos, [:path])
  end
end
