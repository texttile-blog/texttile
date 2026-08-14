defmodule Texttile.ArticlesAuthorTest do
  @moduledoc """
  Who an entry is by: whoever started it, until the editor names
  another account. The overviews and the reader's page name them
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

    read = Texttile.Articles.Reading.post(article.publish_date, article.slug, :reader)
    assert Articles.author_name(read) == "kb"
  end

  test "the author moves to another account, and every screen follows" do
    kb = user_fixture(%{username: "kb"})
    anna = user_fixture(%{username: "anna"})
    article = published_post(user: kb, title: "Harbor mornings")

    {:ok, moved} = Articles.set_author(article, anna.id, by: kb)

    assert moved.user_id == anna.id
    assert Articles.author_name(moved) == "anna"

    [listed] = Articles.list_published()
    assert Articles.author_name(listed) == "anna"

    read = Texttile.Articles.Reading.post(article.publish_date, article.slug, :reader)
    assert Articles.author_name(read) == "anna"
  end

  test "an entry whose author has gone takes a new one" do
    kb = user_fixture(%{username: "kb"})
    leaving = user_fixture(%{username: "leaving"})
    article = published_post(user: leaving, title: "Harbor mornings")
    {:ok, _} = Accounts.delete_user(leaving, by: kb)

    {:ok, named} = article.id |> Articles.get_article!() |> Articles.set_author(kb.id, by: kb)

    assert Articles.author_name(named) == "kb"
  end

  # Every entry is somebody's. The field offers the accounts and
  # nothing else, and a request for nobody changes nothing.
  test "nobody is not an author" do
    kb = user_fixture(%{username: "kb"})
    article = published_post(user: kb, title: "Harbor mornings")

    assert {:error, _} = Articles.set_author(article, nil, by: kb)
    assert {:error, _} = Articles.set_author(article, "", by: kb)

    assert article.id |> Articles.get_article!() |> Articles.author_name() == "kb"
  end

  test "an account that does not exist cannot become the author" do
    kb = user_fixture(%{username: "kb"})
    article = published_post(user: kb, title: "Harbor mornings")

    assert {:error, _} = Articles.set_author(article, kb.id + 1000, by: kb)
    assert article.id |> Articles.get_article!() |> Articles.author_name() == "kb"
  end

  test "the move is a line in the Log" do
    kb = user_fixture(%{username: "kb"})
    anna = user_fixture(%{username: "anna"})
    article = published_post(user: kb, title: "Harbor mornings")

    {:ok, moved} = Articles.set_author(article, anna.id, by: kb)

    assert [%{text: text} | _] = Articles.log(moved)
    assert text =~ "anna"
  end
end
