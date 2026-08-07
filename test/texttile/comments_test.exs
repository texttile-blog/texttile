defmodule Texttile.CommentsTest do
  use Texttile.DataCase, async: false

  import Swoosh.TestAssertions
  import Texttile.ArticlesFixtures

  alias Texttile.Articles
  alias Texttile.Comments
  alias Texttile.Settings

  @attrs %{"name" => "Grandma Christel", "email" => "christel@example.org", "body" => "More of the dog, please."}

  defp post!(article, attrs \\ @attrs) do
    {:ok, comment} = Comments.post(article, attrs, confirm_url: &"http://test/comments/confirm/#{&1}")
    comment
  end

  describe "post/3" do
    test "stores the comment on its text, waiting for the reader" do
      article = published_post()
      comment = post!(article)

      assert comment.name == "Grandma Christel"
      assert comment.body == "More of the dog, please."
      assert comment.article_id == article.id
      assert comment.address.email == "christel@example.org"
      refute Comments.shown_to_readers?(comment)

      assert_email_sent(fn mail ->
        assert mail.to == [{"Grandma Christel", "christel@example.org"}]
        assert mail.text_body =~ "http://test/comments/confirm/"
      end)
    end

    test "announces the comment" do
      article = published_post()
      Comments.subscribe()
      comment = post!(article)
      id = comment.id
      assert_receive {:comment_posted, %Comments.Comment{id: ^id}}
    end

    test "a confirmed address never waits and never gets another mail" do
      article = published_post()
      first = post!(article)
      {:ok, _} = Comments.confirm(first.address.token)

      second = post!(article)
      assert Comments.shown_to_readers?(second)

      # one mail for the first comment, none for the second
      assert_email_sent()
      refute_email_sent()
    end

    test "an unconfirmed address gets the same link again with the next comment" do
      article = published_post()
      first = post!(article)
      second = post!(article)

      assert second.address_id == first.address_id
      assert_email_sent(text_body: ~r/#{first.address.token}/)
      assert_email_sent(text_body: ~r/#{first.address.token}/)
    end

    test "while confirmation is off, no mail goes and the comment shows at once" do
      {:ok, _} = Settings.put(:comments_require_confirmation, false)
      article = published_post()
      comment = post!(article)

      assert Comments.shown_to_readers?(comment)
      refute_email_sent()

      # the switch turned back on hides the unconfirmed comment again
      {:ok, _} = Settings.put(:comments_require_confirmation, true)
      refute Comments.shown_to_readers?(Comments.get_comment!(comment.id))
    end

    test "the address is one row, case and spaces folded" do
      article = published_post()
      a = post!(article, %{@attrs | "email" => " Christel@Example.org "})
      b = post!(article)
      assert a.address_id == b.address_id
      assert a.address.email == "christel@example.org"
    end

    test "a closed text takes no comment" do
      article = published_post()
      {:ok, article} = Articles.update_settings(article, %{allow_comments: false})

      assert {:error, :closed} = Comments.post(article, @attrs, confirm_url: &to_string/1)
    end

    test "a draft takes no comment" do
      article = draft_post()
      assert {:error, :closed} = Comments.post(article, @attrs, confirm_url: &to_string/1)
    end

    test "name, email and body are required and sane" do
      article = published_post()

      assert {:error, changeset} =
               Comments.post(article, %{"name" => "", "email" => "nope", "body" => ""},
                 confirm_url: &to_string/1
               )

      assert %{name: _, email: _, body: _} = errors_on(changeset)
    end
  end

  describe "confirm/1" do
    test "confirms the address and answers with the text of the newest comment" do
      article = published_post()
      comment = post!(article)

      assert {:ok, confirmed_article} = Comments.confirm(comment.address.token)
      assert confirmed_article.id == article.id
      assert Comments.shown_to_readers?(Comments.get_comment!(comment.id))
    end

    test "confirming announces the change" do
      article = published_post()
      comment = post!(article)
      Comments.subscribe()
      {:ok, _} = Comments.confirm(comment.address.token)
      assert_receive {:comments_confirmed, _address_id}
    end

    test "an unknown token is an error" do
      assert :error = Comments.confirm("no-such-token")
    end

    test "a second visit of the link still works" do
      article = published_post()
      comment = post!(article)
      assert {:ok, _} = Comments.confirm(comment.address.token)
      assert {:ok, _} = Comments.confirm(comment.address.token)
    end
  end

  describe "reading and counting" do
    test "for_article/1 answers newest first, recent/1 spans all texts" do
      a = published_post(%{title: "A"})
      b = published_post(%{title: "B"})
      first = post!(a)
      second = post!(b, %{@attrs | "body" => "Second"})
      third = post!(a, %{@attrs | "body" => "Third"})

      assert Enum.map(Comments.for_article(a.id), & &1.id) == [third.id, first.id]
      assert Enum.map(Comments.recent(2), & &1.id) == [third.id, second.id]
      assert Comments.total_count() == 3
      assert Comments.count_map() == %{a.id => 2, b.id => 1}
      assert Comments.waiting_count() == 3

      {:ok, _} = Comments.confirm(first.address.token)
      assert Comments.waiting_count() == 0
    end
  end

  describe "delete_comment/1" do
    test "removes the comment and announces it" do
      article = published_post()
      comment = post!(article)
      Comments.subscribe()

      assert {:ok, _} = Comments.delete_comment(comment)
      assert Comments.for_article(article.id) == []
      assert_receive {:comment_deleted, %Comments.Comment{}}
    end
  end

  test "deleting the text takes its comments with it" do
    article = published_post()
    comment = post!(article)
    {:ok, _} = Articles.delete_article(Articles.get_article!(article.id))
    assert Comments.for_article(article.id) == []
    assert_raise Ecto.NoResultsError, fn -> Comments.get_comment!(comment.id) end
  end
end
