defmodule Texttile.NewsletterTest do
  use Texttile.DataCase, async: false

  import Swoosh.TestAssertions
  import Texttile.ArticlesFixtures

  alias Texttile.Articles
  alias Texttile.Newsletter
  alias Texttile.Settings

  @email "reader@example.org"

  defp join!(email \\ @email) do
    {:ok, subscriber} =
      Newsletter.join(email, confirm_url: &"http://test/newsletter/confirm/#{&1}")

    subscriber
  end

  describe "join/2" do
    test "stores the address unconfirmed and mails the link" do
      subscriber = join!()

      assert subscriber.email == @email
      refute Newsletter.Subscriber.confirmed?(subscriber)

      assert_email_sent(fn mail ->
        assert mail.to == [{"", @email}]
        assert mail.subject == "Confirm your email on Texttile"
        assert mail.text_body =~ "http://test/newsletter/confirm/#{subscriber.token}"
      end)
    end

    test "announces the change" do
      Newsletter.subscribe()
      join!()
      assert_receive {:newsletter_changed}
    end

    test "the address is one row, case and spaces folded" do
      a = join!(" Reader@Example.org ")
      b = join!()
      assert a.id == b.id
      assert a.email == @email
    end

    test "one address gets one link an hour" do
      first = join!()
      assert_email_sent()

      join!()
      refute_email_sent()

      first
      |> Ecto.Changeset.change(
        confirmation_mailed_at: DateTime.add(DateTime.utc_now(:second), -3601)
      )
      |> Texttile.Repo.update!()

      join!()
      assert_email_sent(text_body: ~r/#{first.token}/)
    end

    test "a confirmed address gets no mail and stays confirmed" do
      first = join!()
      {:ok, _} = Newsletter.confirm(first.token)
      assert_email_sent()

      second = join!()
      assert Newsletter.Subscriber.confirmed?(second)
      refute_email_sent()
    end

    test "an address that is not one is refused" do
      assert {:error, :invalid} = Newsletter.join("nope", confirm_url: &to_string/1)
      assert {:error, :invalid} = Newsletter.join("", confirm_url: &to_string/1)
      assert Newsletter.list() == []
    end
  end

  describe "confirm/1" do
    test "confirms the address, once and for all visits of the link" do
      subscriber = join!()

      assert {:ok, confirmed} = Newsletter.confirm(subscriber.token)
      assert Newsletter.Subscriber.confirmed?(confirmed)
      assert {:ok, _again} = Newsletter.confirm(subscriber.token)
    end

    test "announces the change" do
      subscriber = join!()
      Newsletter.subscribe()
      {:ok, _} = Newsletter.confirm(subscriber.token)
      assert_receive {:newsletter_changed}
    end

    test "an unknown token is an error" do
      assert :error = Newsletter.confirm("no-such-token")
    end
  end

  describe "add/1, the admin way" do
    test "stores the address confirmed, and no mail travels" do
      assert {:ok, subscriber} = Newsletter.add(@email)
      assert Newsletter.Subscriber.confirmed?(subscriber)
      refute_email_sent()
    end

    test "an address that already waits is confirmed by it" do
      waiting = join!()
      refute Newsletter.Subscriber.confirmed?(waiting)

      assert {:ok, added} = Newsletter.add(@email)
      assert added.id == waiting.id
      assert Newsletter.Subscriber.confirmed?(added)
    end

    test "an address that is not one is refused" do
      assert {:error, :invalid} = Newsletter.add("nope")
    end

    test "announces the change" do
      Newsletter.subscribe()
      {:ok, _} = Newsletter.add(@email)
      assert_receive {:newsletter_changed}
    end
  end

  describe "unsubscribe/1 and remove/1" do
    test "the token takes its address off the list, however often it is used" do
      subscriber = join!()
      assert Newsletter.by_token(subscriber.token)

      assert :ok = Newsletter.unsubscribe(subscriber.token)
      assert Newsletter.list() == []
      assert :ok = Newsletter.unsubscribe(subscriber.token)
    end

    test "remove/1 takes a subscriber off the admin list" do
      {:ok, subscriber} = Newsletter.add(@email)
      Newsletter.subscribe()

      assert {:ok, _} = Newsletter.remove(subscriber.id)
      assert Newsletter.list() == []
      assert_receive {:newsletter_changed}
      assert {:error, :gone} = Newsletter.remove(subscriber.id)
    end
  end

  describe "list/0 and the counts" do
    test "newest first, and the counts tell confirmed from waiting" do
      {:ok, _} = Newsletter.add("one@example.org")
      join!("two@example.org")

      assert [%{email: "two@example.org"}, %{email: "one@example.org"}] = Newsletter.list()
      assert Newsletter.confirmed_count() == 1
      assert [%{email: "one@example.org"}] = Newsletter.confirmed()
    end
  end

  describe "the publish email" do
    setup do
      Application.put_env(:swoosh, :shared_test_process, self())
      on_exit(fn -> Application.delete_env(:swoosh, :shared_test_process) end)

      {:ok, _} = Newsletter.add("one@example.org")
      {:ok, _} = Newsletter.add("two@example.org")
      :ok
    end

    test "publishing a post mails every confirmed subscriber, once" do
      join!("waiting@example.org")
      # the join mail, out of the way
      assert_receive {:email, _}, 1000

      article = published_post(title: "Harbor mornings", body: "Fog over the pier.")

      assert_receive {:email, %Swoosh.Email{} = first}, 1000
      assert_receive {:email, %Swoosh.Email{} = second}, 1000
      refute_receive {:email, _}, 200

      assert Enum.sort(Enum.map([first, second], &elem(hd(&1.to), 1))) ==
               ["one@example.org", "two@example.org"]

      assert first.subject =~ "Harbor mornings"
      assert first.text_body =~ Articles.public_path(article)
      assert first.text_body =~ "Fog over the pier."
      assert first.text_body =~ "/newsletter/unsubscribe/"

      # the same way off, where the mail program reads it
      assert %{"List-Unsubscribe" => header} = first.headers
      assert header =~ ~r"\A<http://[^\s>]+/newsletter/unsubscribe/[^\s>]+>\z"

      assert Articles.get_article!(article.id).notified_on == Date.utc_today()
    end

    test "publishing again mails nobody a second time" do
      article = published_post()
      assert_receive {:email, _}, 1000
      assert_receive {:email, _}, 1000

      user = Texttile.AccountsFixtures.user_fixture()
      article = Articles.get_article!(article.id)
      {:ok, article} = Articles.unpublish(article, user)
      {:ok, _} = Articles.publish(article, user)

      refute_receive {:email, _}, 200
    end

    test "a second go-live that read the text before the stamp mails nobody" do
      article = published_post()
      assert_receive {:email, _}, 1000
      assert_receive {:email, _}, 1000

      # another admin, or the go-live clock, holding the text as it
      # stood before the stamp landed
      stale = %{Articles.get_article!(article.id) | notified_on: nil}
      answered = Newsletter.notify_published(stale)

      refute_receive {:email, _}, 200
      assert answered.notified_on == Date.utc_today()
    end

    test "a page goes live silently" do
      published_page()
      refute_receive {:email, _}, 200
    end

    test "an unchecked text goes live silently and stays unsent" do
      user = Texttile.AccountsFixtures.user_fixture()
      article = draft_post(user: user)
      {:ok, article} = Articles.update_settings(article, %{notify_on_publish: false})
      {:ok, article} = Articles.publish(article, user)

      refute_receive {:email, _}, 200
      assert is_nil(article.notified_on)
    end

    test "a scheduled text mails at go-live, not at scheduling" do
      article = scheduled_post()
      refute_receive {:email, _}, 200

      [gone_live] = Articles.go_live_due(article.publish_date)
      assert gone_live.id == article.id
      assert gone_live.notified_on == Date.utc_today()

      assert_receive {:email, _}, 1000
      assert_receive {:email, _}, 1000
    end

    test "dragging a scheduled date to today is a go-live and mails" do
      user = Texttile.AccountsFixtures.user_fixture()
      article = scheduled_post(user: user)

      {:ok, article} = Articles.set_publish_date(article, user, Date.utc_today())
      assert article.status == "published"
      assert article.notified_on == Date.utc_today()
      assert_receive {:email, _}, 1000
    end

    test "moving the date of a live text mails nobody" do
      user = Texttile.AccountsFixtures.user_fixture()

      article =
        published_post(user: user, publish_date: Date.add(Date.utc_today(), -3))

      assert_receive {:email, _}, 1000
      assert_receive {:email, _}, 1000
      article = Articles.get_article!(article.id)

      # take the stamp away, as an old import would stand
      {:ok, article} =
        article |> Texttile.Articles.Article.state_changeset(%{notified_on: nil}) |> Repo.update()

      {:ok, moved} = Articles.set_publish_date(article, user, Date.add(Date.utc_today(), -1))
      assert moved.status == "published"
      refute_receive {:email, _}, 200
    end

    test "the mail names the access word while the blog asks for one" do
      {:ok, _} = Settings.put(:site_visibility, "protected")
      {:ok, _} = Settings.put(:site_password, "sesame")

      published_post()
      assert_receive {:email, mail}, 1000
      assert mail.text_body =~ "sesame"
    end

    test "an open blog's mail carries no access word" do
      published_post()
      assert_receive {:email, mail}, 1000
      refute mail.text_body =~ "access word"
    end

    test "with nobody on the list the text still goes live, marked" do
      Enum.each(Newsletter.list(), &Newsletter.remove(&1.id))

      article = published_post()
      refute_receive {:email, _}, 200
      assert Articles.get_article!(article.id).notified_on == Date.utc_today()
    end
  end
end
