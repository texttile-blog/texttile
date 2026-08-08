defmodule Texttile.Stats.View do
  @moduledoc """
  One counted view of one reader page.

  Nothing in the row names a person. `visitor` is a hash of the day's
  salt, the caller's address and their browser line, and the salt is
  thrown away at midnight: from tomorrow on, the same reader hashes to
  something else and no row can be traced back. The address itself is
  never written anywhere.
  """

  use Ecto.Schema

  schema "page_views" do
    field :day, :date
    field :path, :string
    field :article_id, :integer
    field :visitor, :string
    field :referrer_host, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
