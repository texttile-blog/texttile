defmodule Texttile.CommentsTest do
  use Texttile.DataCase, async: false

  import Swoosh.TestAssertions
  import Texttile.ArticlesFixtures

  alias Texttile.Articles
  alias Texttile.Comments
  alias Texttile.Settings

  @attrs %{
    "name" => "Grandma Christel",
    "email" => "christel@example.org",
    "body" => "More of the dog, please."
  }

  defp post!(article, attrs \\ @attrs) do
    {:ok, comment} =
      Comments.post(article, attrs, confirm_url: &"http://test/comments/confirm/#{&1}")

    comment
  end

  # The confirmation link travels to the reader from this process; the
  # mail to the people who run the blog leaves a task of its own. Both
  # land in the same test mailbox, so this picks out the second kind.
  defp admin_mail(timeout \\ 1000) do
    receive do
      {:email, %Swoosh.Email{} = mail} ->
        if mail.subject =~ "New comment", do: mail, else: admin_mail(timeout)
    after
      timeout -> nil
    end
  end

  describe "post/3" do
    # Every mail asserted here is the one the reader gets. The mail to
    # the people who run the blog has a block of its own, and it would
    # otherwise stand in this one's mailbox.
    setup do
      {:ok, _} = Settings.put(:notify_on_comment, false)
      :ok
    end

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

    test "a second comment from one address joins it, and the link stays the one" do
      article = published_post()
      first = post!(article)
      second = post!(article)

      assert second.address_id == first.address_id
      assert second.address.token == first.address.token
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

    test "a name or a comment beyond the limit is refused" do
      article = published_post()

      assert {:error, changeset} =
               Comments.post(article, %{@attrs | "name" => String.duplicate("n", 121)},
                 confirm_url: &to_string/1
               )

      assert %{name: _} = errors_on(changeset)

      assert {:error, changeset} =
               Comments.post(article, %{@attrs | "body" => String.duplicate("b", 4001)},
                 confirm_url: &to_string/1
               )

      assert %{body: _} = errors_on(changeset)
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

  describe "the confirmation mail" do
    setup do
      {:ok, _} = Settings.put(:notify_on_comment, false)
      :ok
    end

    test "one address gets one link an hour, however many comments it writes" do
      article = published_post()
      first = post!(article)
      assert_email_sent()

      post!(article, %{@attrs | "body" => "Again"})
      refute_email_sent()

      # an hour later the link travels again, so a lost mail is no dead end
      first.address
      |> Ecto.Changeset.change(
        confirmation_mailed_at: DateTime.add(DateTime.utc_now(:second), -3601)
      )
      |> Texttile.Repo.update!()

      post!(article, %{@attrs | "body" => "Much later"})
      assert_email_sent(text_body: ~r/#{first.address.token}/)
    end
  end

  describe "the mail to the people who run the blog" do
    setup do
      Application.put_env(:swoosh, :shared_test_process, self())
      on_exit(fn -> Application.delete_env(:swoosh, :shared_test_process) end)
      :ok
    end

    test "with confirmation off, the comment travels the moment it arrives" do
      {:ok, _} = Settings.put(:comments_require_confirmation, false)
      kb = Texttile.AccountsFixtures.user_fixture(%{username: "kb"})
      article = published_post(title: "Harbor mornings", user: kb)

      post!(article)

      assert mail = admin_mail()
      assert mail.to == [{Texttile.Accounts.display_name(kb), kb.email}]
      assert mail.subject =~ "Harbor mornings"
      assert mail.text_body =~ "Grandma Christel"
      assert mail.text_body =~ "More of the dog, please."
      assert mail.text_body =~ Articles.public_path(article)
      assert mail.text_body =~ "/admin/comments"
      assert mail.text_body =~ "stands under the text"
      # the address of the reader is nowhere in it
      refute mail.text_body =~ "christel@example.org"
    end

    # Until the reader has followed the link, nobody has proved the
    # address is theirs. Mailing the comment on before that would turn
    # the form into a way to write to everybody who runs the blog.
    test "a comment that still waits for its reader mails nobody" do
      kb = Texttile.AccountsFixtures.user_fixture(%{username: "kb"})
      article = published_post(user: kb)

      comment = post!(article)

      refute admin_mail(300)

      # the link is followed, and the same comment travels
      {:ok, _article} = Comments.confirm(comment.address.token)

      assert mail = admin_mail()
      assert mail.text_body =~ "More of the dog, please."
      assert mail.text_body =~ "stands under the text"
    end

    test "a confirmed address travels at once with every later comment" do
      kb = Texttile.AccountsFixtures.user_fixture(%{username: "kb"})
      article = published_post(user: kb)

      comment = post!(article)
      {:ok, _article} = Comments.confirm(comment.address.token)
      assert admin_mail()

      post!(article, %{@attrs | "body" => "One more thing"})

      assert mail = admin_mail()
      assert mail.text_body =~ "One more thing"
    end

    # An address may hold a link from a time when the blog asked for
    # one. Following it later must not mail words that travelled the
    # moment they arrived.
    test "with confirmation off, a late confirmation mails nothing twice" do
      {:ok, _} = Settings.put(:comments_require_confirmation, false)
      kb = Texttile.AccountsFixtures.user_fixture(%{username: "kb"})
      article = published_post(user: kb)

      comment = post!(article)
      assert admin_mail()

      {:ok, _article} = Comments.confirm(comment.address.token)

      refute admin_mail(300)
    end

    test "switched off in the settings, nothing is mailed" do
      {:ok, _} = Settings.put(:notify_on_comment, false)
      {:ok, _} = Settings.put(:comments_require_confirmation, false)
      kb = Texttile.AccountsFixtures.user_fixture(%{username: "kb"})
      article = published_post(user: kb)

      post!(article)

      refute admin_mail(300)
    end

    test "everybody with an account gets their own mail" do
      {:ok, _} = Settings.put(:comments_require_confirmation, false)
      kb = Texttile.AccountsFixtures.user_fixture(%{username: "kb"})
      julia = Texttile.AccountsFixtures.user_fixture(%{username: "julia"})

      article = published_post(user: kb)
      post!(article)

      addressed =
        [admin_mail(), admin_mail()]
        |> Enum.map(fn mail -> mail.to |> hd() |> elem(1) end)
        |> Enum.sort()

      assert addressed == Enum.sort([kb.email, julia.email])
      refute admin_mail(300)
    end
  end

  describe "reading and counting" do
    test "for_readers/1 answers oldest first and caps what one page carries" do
      article = published_post()

      for n <- 1..3 do
        post!(article, %{@attrs | "email" => "reader#{n}@example.org", "body" => "Words #{n}"})
      end

      assert {rows, 0} = Comments.for_readers(article.id)
      assert Enum.map(rows, & &1.body) == ["Words 1", "Words 2", "Words 3"]
      assert Comments.count_for(article.id) == 3
    end

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

    test "the row stays, stamped for the end of the trash window" do
      article = published_post()
      comment = post!(article)

      assert {:ok, deleted} = Comments.delete_comment(comment)
      assert DateTime.diff(deleted.delete_after, DateTime.utc_now(), :day) in 29..30
      assert Texttile.Repo.get(Comments.Comment, comment.id)
    end

    test "a comment somebody deleted first is gone, not an error" do
      article = published_post()
      comment = post!(article)

      assert {:ok, _} = Comments.delete_comment(comment)
      assert {:error, :gone} = Comments.delete_comment(comment)
      assert {:error, :gone} = Comments.delete_comment(comment.id)
      assert Comments.get_comment(comment.id) == nil
    end

    test "deleting by id takes the comment" do
      article = published_post()
      comment = post!(article)

      assert {:ok, _} = Comments.delete_comment(comment.id)
      assert Comments.for_article(article.id) == []
    end
  end

  describe "the trash" do
    test "a deleted comment leaves every list and every count" do
      article = published_post()
      kept = post!(article, %{@attrs | "email" => "jens@example.org", "body" => "Kept"})
      gone = post!(article)

      {:ok, _} = Comments.delete_comment(gone)

      assert Enum.map(Comments.for_article(article.id), & &1.id) == [kept.id]
      assert Enum.map(Comments.recent(10), & &1.id) == [kept.id]
      assert Comments.total_count() == 1
      assert Comments.count_for(article.id) == 1
      assert Comments.count_map() == %{article.id => 1}
      assert Comments.waiting_count() == 1
      assert {[%{id: id}], 0} = Comments.for_readers(article.id)
      assert id == kept.id
      assert Comments.get_comment(gone.id) == nil
    end

    test "the trash holds it, with its text, until it is restored" do
      article = published_post(title: "Harbor mornings")
      comment = post!(article)
      {:ok, _} = Comments.delete_comment(comment)

      assert [trashed] = Comments.trashed()
      assert trashed.id == comment.id
      assert trashed.article.title == "Harbor mornings"
      assert trashed.address.email == "christel@example.org"
      assert Comments.trashed_count() == 1

      Comments.subscribe()
      assert {:ok, restored} = Comments.restore_comment(comment.id)
      assert restored.delete_after == nil
      assert Comments.trashed() == []
      assert Enum.map(Comments.for_article(article.id), & &1.id) == [comment.id]
      assert_receive {:comment_changed, %Comments.Comment{}}
    end

    test "restoring what nobody deleted, twice, or never existed is gone" do
      article = published_post()
      comment = post!(article)

      assert {:error, :gone} = Comments.restore_comment(comment.id)
      {:ok, _} = Comments.delete_comment(comment)
      assert {:ok, _} = Comments.restore_comment(comment.id)
      assert {:error, :gone} = Comments.restore_comment(comment.id)
      assert {:error, :gone} = Comments.restore_comment(comment.id + 1000)
    end

    test "sweep_due/0 takes what the window has run out on, and leaves the rest" do
      article = published_post()
      due = post!(article)
      waiting = post!(article, %{@attrs | "email" => "jens@example.org", "body" => "Later"})

      {:ok, _} = Comments.delete_comment(due)
      {:ok, _} = Comments.delete_comment(waiting)

      due
      |> Ecto.Changeset.change(delete_after: DateTime.add(DateTime.utc_now(:second), -1))
      |> Texttile.Repo.update!()

      assert Comments.sweep_due() == 1
      assert Texttile.Repo.get(Comments.Comment, due.id) == nil
      assert Texttile.Repo.get(Comments.Comment, waiting.id)
    end

    test "a comment in the trash takes no edit and no release" do
      article = published_post()
      comment = post!(article)
      {:ok, _} = Comments.delete_comment(comment)

      assert {:error, :gone} = Comments.edit_comment(comment.id, "Rewritten")
      assert {:error, :gone} = Comments.release_comment(comment.id)
    end
  end

  describe "edit_comment/2" do
    test "changes the words, keeps the name and the address, and marks the edit" do
      article = published_post()
      comment = post!(article)
      Comments.subscribe()

      assert {:ok, edited} = Comments.edit_comment(comment.id, "  Less of the dog, please.  ")
      assert edited.body == "Less of the dog, please."
      assert edited.name == "Grandma Christel"
      assert edited.address_id == comment.address_id
      assert Comments.edited?(edited)
      refute Comments.edited?(comment)
      assert_receive {:comment_changed, %Comments.Comment{}}
    end

    test "readers get the new words at once" do
      {:ok, _} = Settings.put(:comments_require_confirmation, false)
      article = published_post()
      comment = post!(article)

      {:ok, _} = Comments.edit_comment(comment.id, "Rewritten")

      assert {[shown], 0} = Comments.for_readers(article.id)
      assert shown.body == "Rewritten"
    end

    test "empty words are refused and the limit still holds" do
      article = published_post()
      comment = post!(article)

      assert {:error, changeset} = Comments.edit_comment(comment.id, "   ")
      assert %{body: _} = errors_on(changeset)

      assert {:error, changeset} =
               Comments.edit_comment(comment.id, String.duplicate("b", 4001))

      assert %{body: _} = errors_on(changeset)
      assert Comments.get_comment!(comment.id).body == "More of the dog, please."
    end

    test "a comment that is already gone is gone" do
      article = published_post()
      comment = post!(article)
      assert {:error, :gone} = Comments.edit_comment(comment.id + 1000, "Nothing")
      assert {:ok, _} = Comments.edit_comment(comment.id, "Something")
    end
  end

  describe "release_comment/1" do
    setup do
      Application.put_env(:swoosh, :shared_test_process, self())
      on_exit(fn -> Application.delete_env(:swoosh, :shared_test_process) end)
      :ok
    end

    test "one comment stands under the text while its address stays unconfirmed" do
      article = published_post()
      comment = post!(article)
      refute Comments.shown_to_readers?(comment)

      Comments.subscribe()
      assert {:ok, released} = Comments.release_comment(comment.id)
      assert Comments.shown_to_readers?(released)
      assert Comments.released?(released)
      assert_receive {:comment_changed, %Comments.Comment{}}

      # the address itself proved nothing, so the next comment waits again
      later = post!(article, %{@attrs | "body" => "And another thing"})
      refute Comments.shown_to_readers?(later)
      refute Comments.released?(later)
      assert Comments.waiting_count() == 1
    end

    test "a released comment no longer waits" do
      article = published_post()
      comment = post!(article)
      assert Comments.waiting_count() == 1

      {:ok, _} = Comments.release_comment(comment.id)
      assert Comments.waiting_count() == 0
    end

    test "releasing mails nobody: the desk did it" do
      kb = Texttile.AccountsFixtures.user_fixture(%{username: "kb"})
      article = published_post(user: kb)
      comment = post!(article)

      {:ok, _} = Comments.release_comment(comment.id)

      refute admin_mail(300)
    end

    test "a later confirmation does not mail the released words twice" do
      kb = Texttile.AccountsFixtures.user_fixture(%{username: "kb"})
      article = published_post(user: kb)

      released = post!(article)
      still_waiting = post!(article, %{@attrs | "body" => "The second one"})
      {:ok, _} = Comments.release_comment(released.id)

      {:ok, _} = Comments.confirm(released.address.token)

      assert mail = admin_mail()
      assert mail.text_body =~ still_waiting.body
      refute admin_mail(300)
    end

    test "an unknown comment is gone" do
      assert {:error, :gone} = Comments.release_comment(123_456)
    end
  end

  test "deleting the text takes its comments with it, the trashed ones too" do
    article = published_post()
    comment = post!(article)
    trashed = post!(article, %{@attrs | "email" => "jens@example.org", "body" => "Trashed"})
    {:ok, _} = Comments.delete_comment(trashed)

    {:ok, _} = Articles.delete_article(Articles.get_article!(article.id))

    assert Comments.for_article(article.id) == []
    assert Comments.trashed() == []
    assert_raise Ecto.NoResultsError, fn -> Comments.get_comment!(comment.id) end
  end
end
