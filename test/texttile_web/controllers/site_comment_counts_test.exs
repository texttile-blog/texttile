defmodule TexttileWeb.SiteCommentCountsTest do
  @moduledoc """
  How many comments stand under a text, on the cards a reader meets:
  the blog list and the tag archives. The number is the one under the
  text, so a comment that still waits for its reader counts for nobody.
  """
  use TexttileWeb.ConnCase, async: false

  import Texttile.ArticlesFixtures

  alias Texttile.Comments
  alias Texttile.Settings

  defp comment(article, email, body) do
    {:ok, comment} =
      Comments.post(article, %{"name" => "A reader", "email" => email, "body" => body},
        confirm_url: &"http://example.org/comments/confirm/#{&1}"
      )

    comment
  end

  describe "the card of a text" do
    test "carries the count once a comment stands under the text", %{conn: conn} do
      {:ok, _} = Settings.put(:comments_require_confirmation, false)
      article = published_post(title: "The harbour", tags: "sea")

      html = conn |> get(~p"/blog") |> html_response(200)
      refute html =~ "comment"

      comment(article, "one@example.org", "First words")
      html = conn |> get(~p"/blog") |> html_response(200)
      assert html =~ "1 comment"

      comment(article, "two@example.org", "Later words")
      html = conn |> get(~p"/blog") |> html_response(200)
      assert html =~ "2 comments"

      # the tag archive draws the same card, so it says the same
      assert conn |> get(~p"/tags/sea") |> html_response(200) =~ "2 comments"
    end

    test "counts only what readers see", %{conn: conn} do
      {:ok, _} = Settings.put(:comments_require_confirmation, true)
      article = published_post(title: "The harbour")

      waiting = comment(article, "one@example.org", "Still waiting")

      html = conn |> get(~p"/blog") |> html_response(200)
      refute html =~ "1 comment"

      {:ok, _} = Comments.confirm(waiting.address.token)

      html = conn |> get(~p"/blog") |> html_response(200)
      assert html =~ "1 comment"
    end

    test "a comment an admin let through counts too", %{conn: conn} do
      {:ok, _} = Settings.put(:comments_require_confirmation, true)
      article = published_post(title: "The harbour")

      released = comment(article, "one@example.org", "Let through")
      {:ok, _} = Comments.release_comment(released.id)

      assert conn |> get(~p"/blog") |> html_response(200) =~ "1 comment"
    end

    test "a deleted comment leaves the count", %{conn: conn} do
      {:ok, _} = Settings.put(:comments_require_confirmation, false)
      article = published_post(title: "The harbour")

      gone = comment(article, "one@example.org", "Not for long")
      assert conn |> get(~p"/blog") |> html_response(200) =~ "1 comment"

      {:ok, _} = Comments.delete_comment(gone.id)
      refute conn |> get(~p"/blog") |> html_response(200) =~ "1 comment"
    end
  end
end
