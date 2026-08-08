defmodule Texttile.Articles.Redirect do
  @moduledoc """
  An address an entry used to live at.

  A post lives under the day it went live, so its address carries both
  the date and the slug. Changing either one moves the entry, and the
  link somebody already shared points at nothing. This row is what
  keeps that link alive: the site answers the old address with a
  permanent redirect to the new one.

  Only a live entry leaves one behind. Before an entry goes live no
  reader ever had the address, so there is nothing to keep.
  """

  use Ecto.Schema

  schema "article_redirects" do
    field :path, :string
    belongs_to :article, Texttile.Articles.Article

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
