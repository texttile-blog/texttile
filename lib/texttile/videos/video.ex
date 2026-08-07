defmodule Texttile.Videos.Video do
  @moduledoc """
  What the CMS knows about one uploaded video. The row is found by the
  path of the original, which is the name the body and the gallery
  carry; the derived files hang off it.

  `state` is the whole story of the conversion: `queued`, `running`,
  `done`, `failed`.
  """
  use Ecto.Schema

  schema "videos" do
    field :path, :string
    field :mp4_path, :string
    field :poster_path, :string
    field :width, :integer
    field :height, :integer
    field :duration_ms, :integer
    field :state, :string, default: "queued"
    field :error, :string

    timestamps(type: :utc_datetime)
  end
end
