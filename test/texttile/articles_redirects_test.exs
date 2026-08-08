defmodule Texttile.ArticlesRedirectsTest do
  @moduledoc """
  A live entry that moves keeps its old addresses alive. The address of
  a post carries the publish date, so the date moves it exactly as the
  slug does.
  """
  use Texttile.DataCase, async: false

  import Texttile.AccountsFixtures
  import Texttile.ArticlesFixtures

  alias Texttile.Articles

  describe "a live entry that moves" do
    test "keeps the address the slug left behind" do
      article =
        published_post(title: "The harbour", slug: "harbour", publish_date: ~D[2026-08-08])

      {:ok, article} = Articles.update_settings(article, %{slug: "the-harbour"})

      assert [%{path: "/2026/08/08/harbour"}] = Articles.redirects(article)
      assert Articles.redirect_target("/2026/08/08/harbour") == "/2026/08/08/the-harbour"
    end

    test "keeps the address the date left behind" do
      user = user_fixture()

      article =
        published_post(
          title: "The harbour",
          slug: "harbour",
          publish_date: ~D[2026-08-08],
          user: user
        )

      {:ok, article} = Articles.set_publish_date(article, user, ~D[2026-08-01])

      assert [%{path: "/2026/08/08/harbour"}] = Articles.redirects(article)
      assert Articles.redirect_target("/2026/08/08/harbour") == "/2026/08/01/harbour"
    end

    test "collects one row per move, newest first" do
      user = user_fixture()

      article =
        published_post(slug: "one", publish_date: ~D[2026-08-08], user: user)

      {:ok, article} = Articles.update_settings(article, %{slug: "two"})
      {:ok, article} = Articles.set_publish_date(article, user, ~D[2026-08-09])

      assert ["/2026/08/08/two", "/2026/08/08/one"] =
               article |> Articles.redirects() |> Enum.map(& &1.path)
    end

    test "drops the row again when it moves back" do
      article = published_post(slug: "harbour", publish_date: ~D[2026-08-08])
      {:ok, article} = Articles.update_settings(article, %{slug: "quay"})
      {:ok, article} = Articles.update_settings(article, %{slug: "harbour"})

      assert ["/2026/08/08/quay"] = article |> Articles.redirects() |> Enum.map(& &1.path)
      assert Articles.redirect_target("/2026/08/08/harbour") == nil
    end

    test "keeps the address a change of type left behind" do
      # a page lives at its slug alone, a post under its day: the switch
      # moves the entry as surely as a new slug does
      article = published_post(slug: "about-us", publish_date: ~D[2026-08-08])
      {:ok, article} = Articles.update_settings(article, %{type: "page"})

      assert [%{path: "/2026/08/08/about-us"}] = Articles.redirects(article)
      assert Articles.redirect_target("/2026/08/08/about-us") == "/about-us"
    end

    test "sends every address it ever had to where it stands now" do
      user = user_fixture()
      article = published_post(slug: "one", publish_date: ~D[2026-08-08], user: user)
      {:ok, article} = Articles.update_settings(article, %{slug: "two"})
      {:ok, _article} = Articles.update_settings(article, %{slug: "three"})

      # no chain of hops: both old addresses answer with the address of
      # today, so one redirect is all a reader ever follows
      assert Articles.redirect_target("/2026/08/08/one") == "/2026/08/08/three"
      assert Articles.redirect_target("/2026/08/08/two") == "/2026/08/08/three"
    end

    test "hands the address over when another entry takes it" do
      first = published_post(slug: "harbour", publish_date: ~D[2026-08-08])
      {:ok, _first} = Articles.update_settings(first, %{slug: "quay"})

      second = published_post(slug: "bay", publish_date: ~D[2026-08-08])
      {:ok, second} = Articles.update_settings(second, %{slug: "harbour"})
      {:ok, second} = Articles.update_settings(second, %{slug: "pier"})

      assert Articles.redirect_target("/2026/08/08/harbour") == "/2026/08/08/pier"
      assert Articles.redirects(second) |> Enum.map(& &1.path) |> Enum.member?("/2026/08/08/bay")
    end
  end

  describe "an entry that was never live" do
    test "leaves nothing behind when its slug changes" do
      article = draft_post(title: "The harbour", slug: "harbour")
      {:ok, article} = Articles.update_settings(article, %{slug: "quay"})

      assert Articles.redirects(article) == []
    end
  end

  describe "an old address" do
    test "sends nobody anywhere while the entry is off the site" do
      user = user_fixture()
      article = published_post(slug: "harbour", publish_date: ~D[2026-08-08], user: user)
      {:ok, article} = Articles.update_settings(article, %{slug: "quay"})
      {:ok, _article} = Articles.unpublish(article, user)

      assert Articles.redirect_target("/2026/08/08/harbour") == nil
    end

    test "goes with the entry it belonged to" do
      article = published_post(slug: "harbour", publish_date: ~D[2026-08-08])
      {:ok, article} = Articles.update_settings(article, %{slug: "quay"})
      {:ok, _} = Articles.delete_article(article)

      assert Articles.redirect_target("/2026/08/08/harbour") == nil
    end

    test "can be taken off by hand" do
      article = published_post(slug: "harbour", publish_date: ~D[2026-08-08])
      {:ok, article} = Articles.update_settings(article, %{slug: "quay"})
      [old] = Articles.redirects(article)

      assert :ok = Articles.delete_redirect(article, old.id)
      assert Articles.redirects(article) == []
      assert Articles.redirect_target("/2026/08/08/harbour") == nil
    end

    test "belongs to its own entry and to no other" do
      mine = published_post(slug: "harbour", publish_date: ~D[2026-08-08])
      {:ok, mine} = Articles.update_settings(mine, %{slug: "quay"})
      [old] = Articles.redirects(mine)

      other = published_post(slug: "elsewhere", publish_date: ~D[2026-08-08])
      assert :ok = Articles.delete_redirect(other, old.id)
      assert [_kept] = Articles.redirects(mine)
    end
  end
end
