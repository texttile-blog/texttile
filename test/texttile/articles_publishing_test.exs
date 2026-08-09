defmodule Texttile.Articles.PublishingTest do
  use Texttile.DataCase

  import Texttile.ArticlesFixtures

  alias Texttile.Articles
  alias Texttile.Articles.Publishing
  alias Texttile.Articles.Visibility
  alias Texttile.Newsletter

  setup do
    %{user: Texttile.AccountsFixtures.user_fixture()}
  end

  # publish_date is not a setting, it is a state, so it goes the way
  # the editor's own date field goes.
  defp draft(user, attrs \\ %{}) do
    {date, attrs} = Map.pop(attrs, "publish_date")
    {:ok, article} = Articles.update_settings(draft_post(user: user), attrs)
    if date, do: elem(Articles.set_publish_date(article, user, date), 1), else: article
  end

  defp subscriber! do
    {:ok, subscriber} = Newsletter.add("reader-#{System.unique_integer([:positive])}@example.org")
    subscriber
  end

  describe "choice/1" do
    test "a click on a draft means: publish and mail as the entry says", %{user: user} do
      assert Publishing.choice(draft(user)) == :mail
    end

    # The date is already set and already decided; the click only means
    # "now", so the mail switch stands as it stands.
    test "a click on a scheduled entry keeps the entry's own mail switch", %{user: user} do
      {:ok, scheduled} =
        Articles.publish(draft(user, %{"publish_date" => Date.add(Date.utc_today(), 5)}), user)

      assert Publishing.choice(scheduled) == :as_set
    end
  end

  describe "plan/3" do
    test "a plain click puts the entry live today", %{user: user} do
      plan = Publishing.plan(draft(user), :mail)

      assert plan.status == Visibility.live_status()
      assert plan.live_now?
      assert plan.day == Date.utc_today()
    end

    test "a date in the future schedules instead", %{user: user} do
      later = Date.add(Date.utc_today(), 5)
      plan = Publishing.plan(draft(user, %{"publish_date" => later}), :mail)

      assert plan.status == "scheduled"
      refute plan.live_now?
      assert plan.day == later
    end

    test "publishing a scheduled entry now takes today, whatever date it carries", %{user: user} do
      later = Date.add(Date.utc_today(), 5)
      {:ok, scheduled} = Articles.publish(draft(user, %{"publish_date" => later}), user)

      plan = Publishing.plan(scheduled, Publishing.choice(scheduled))

      assert plan.force?
      assert plan.day == Date.utc_today()
      assert plan.live_now?
    end
  end

  describe "plan/3: who gets a mail" do
    setup do
      subscriber!()
      :ok
    end

    test "the mail goes to the confirmed subscribers", %{user: user} do
      plan = Publishing.plan(draft(user, %{"notify_on_publish" => true}), :mail)

      assert plan.mails?
      assert plan.recipients == 1
    end

    test "publishing quietly mails nobody", %{user: user} do
      plan = Publishing.plan(draft(user, %{"notify_on_publish" => true}), :quiet)

      refute plan.mails?
      assert plan.recipients == 0
    end

    test "a page never mails anybody", %{user: user} do
      plan = Publishing.plan(draft(user, %{"type" => "page", "notify_on_publish" => true}), :mail)

      refute plan.mails?
      assert plan.recipients == 0
    end

    test "a click that only schedules mails nobody yet", %{user: user} do
      later = Date.add(Date.utc_today(), 5)
      article = draft(user, %{"notify_on_publish" => true, "publish_date" => later})

      plan = Publishing.plan(article, :mail)

      assert plan.mails?
      assert plan.recipients == 0
    end

    test "a mail that already went never goes twice", %{user: user} do
      article = draft(user, %{"notify_on_publish" => true})
      {:ok, live} = Publishing.run(article, user, Publishing.plan(article, :mail))

      {:ok, draft_again} = Articles.unpublish(live, user)
      plan = Publishing.plan(draft_again, :mail)

      assert plan.recipients == 0
    end
  end

  describe "run/3" do
    test "carries the plan out and records what the click asked for", %{user: user} do
      article = draft(user, %{"notify_on_publish" => true})

      {:ok, published} = Publishing.run(article, user, Publishing.plan(article, :quiet))

      assert Visibility.live?(published)
      refute published.notify_on_publish
      assert is_nil(published.notified_on)
    end

    test "a future date schedules instead of going live", %{user: user} do
      later = Date.add(Date.utc_today(), 5)
      article = draft(user, %{"publish_date" => later})

      {:ok, scheduled} = Publishing.run(article, user, Publishing.plan(article, :mail))

      assert scheduled.status == "scheduled"
      assert scheduled.publish_date == later
    end

    test "publishing a scheduled entry now brings it to today", %{user: user} do
      later = Date.add(Date.utc_today(), 5)
      article = draft(user, %{"publish_date" => later})
      {:ok, scheduled} = Publishing.run(article, user, Publishing.plan(article, :mail))

      plan = Publishing.plan(scheduled, Publishing.choice(scheduled))
      {:ok, live} = Publishing.run(scheduled, user, plan)

      assert Visibility.live?(live)
      assert live.publish_date == Date.utc_today()
    end
  end
end
