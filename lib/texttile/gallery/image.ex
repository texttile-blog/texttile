defmodule Texttile.Gallery.Image do
  @moduledoc """
  One picture in a text's gallery. The file itself lives below the
  uploads root and is never rewritten; this row carries what the CMS
  knows about it, above all `gallery_date`, the one field every
  ordering of the gallery reads.

  Dates are naive wall-clock time kept as UTC: what the camera wrote is
  what the admin sees and edits, no timezone mathematics anywhere.
  """
  use Ecto.Schema

  schema "gallery_images" do
    belongs_to :article, Texttile.Articles.Article

    field :path, :string
    field :filename, :string
    field :gallery_date, :utc_datetime_usec
    field :width, :integer
    field :height, :integer

    # Set while the ten second undo window is open; the sweeper makes
    # the deletion final when the moment has passed.
    field :delete_after, :utc_datetime_usec

    timestamps(type: :utc_datetime)
  end
end
