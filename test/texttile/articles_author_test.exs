defmodule Texttile.ArticlesAuthorTest do
  @moduledoc """
  Who started an entry. The overviews and the reader's page name them
  beside the day.
  """

  use Texttile.DataCase

  import Texttile.AccountsFixtures
  import Texttile.ArticlesFixtures

  alias Texttile.Accounts
  alias Texttile.Articles

  test "a new entry keeps the person who started it" do
    user = user_fixture(%{username: "kb"})
    {:ok, article} = Articles.create_draft(user)

    assert article.user_id == user.id
    assert Articles.author_name(article) == "kb"
  end

  test "the name is read now, so a rename reaches every entry" do
    user = user_fixture(%{username: "kb"})
    article = published_post(user: user, title: "Harbor mornings")

    {:ok, _} = Accounts.update_display_name(user, "Klaus Breyer")

    assert article.id |> Articles.get_article!() |> Articles.author_name() ==
             "Klaus Breyer"
  end

  # What somebody wrote stays when their account goes; the entry then
  # has no name to show and shows none.
  test "an entry whose author has gone is shown without a name" do
    kb = user_fixture(%{username: "kb"})
    leaving = user_fixture(%{username: "leaving"})
    article = published_post(user: leaving, title: "Harbor mornings")

    {:ok, _} = Accounts.delete_user(leaving, by: kb)

    read = Articles.get_article!(article.id)
    assert read.user_id == nil
    assert Articles.author_name(read) == nil
  end

  test "the name travels with the reader's list and with one entry" do
    user = user_fixture(%{username: "kb"})
    article = published_post(user: user, title: "Harbor mornings")

    [listed] = Articles.list_published()
    assert Articles.author_name(listed) == "kb"

    read = Articles.get_published_post(article.publish_date, article.slug)
    assert Articles.author_name(read) == "kb"
  end
end
