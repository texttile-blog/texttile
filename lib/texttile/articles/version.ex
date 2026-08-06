defmodule Texttile.Articles.Version do
  @moduledoc """
  A deliberate, restorable point in time of the main text: the title
  and the body, full copies, nothing else. Tiles, tags, status and slug
  are shared and live, so versioning them would be a lie.
  """

  use Ecto.Schema

  schema "article_versions" do
    field :title, :string, default: ""
    field :body, :string, default: ""

    belongs_to :article, Texttile.Articles.Article
    belongs_to :user, Texttile.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
