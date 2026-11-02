defmodule Texttile.CommentsFixtures do
  @moduledoc """
  Comments for a test whose subject is the admin's side of them.

  A spam wave is a pile of unconfirmed comments on one entry, and
  `Texttile.Comments.post/3` caps exactly that: past ten a day the
  comment is dropped. A test about the pager, the filter or a bulk
  action needs the pile to exist, so this writes the rows the way they
  would stand had they arrived a day apart.
  """

  alias Texttile.Comments.Address
  alias Texttile.Comments.Comment
  alias Texttile.Repo

  @doc """
  `count` comments that wait for their readers, each from an address of
  its own, on `article`, oldest first. The words are "Words 1" to
  "Words `count`", the names "Reader 1" on. Addresses and the entry are
  loaded, the way the context answers them.
  """
  def wave!(article, count) do
    for n <- 1..count do
      address = Repo.insert!(Address.build("reader#{n}@example.org"))

      %Comment{article_id: article.id, address_id: address.id}
      |> Comment.changeset(%{"name" => "Reader #{n}", "body" => "Words #{n}"})
      |> Repo.insert!()
      |> Map.put(:address, address)
      |> Map.put(:article, article)
    end
  end
end
