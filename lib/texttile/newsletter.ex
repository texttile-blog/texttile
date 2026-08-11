defmodule Texttile.Newsletter do
  @moduledoc """
  The newsletter list, and the one mail it exists for: when a text goes
  live with Email subscribers checked, every confirmed address gets it.

  Two ways onto the list. A reader joins through the form on the site
  and confirms by mail first - until then the address stands on the
  list but gets nothing. An admin adds an address in the admin area,
  and that address is confirmed at once: the admin vouches for it.
  Every mail the list sends carries the way off it. Every change is
  announced on the newsletter topic.
  """

  import Ecto.Query

  require Logger

  alias Texttile.Articles
  alias Texttile.Articles.Article
  alias Texttile.Articles.Reading
  alias Texttile.Confirmation
  alias Texttile.Newsletter.Notifier
  alias Texttile.Newsletter.Subscriber
  alias Texttile.Repo
  alias Texttile.Settings

  @topic "newsletter"

  ## PubSub

  @doc "Subscribes the caller to `{:newsletter_changed}`."
  def subscribe do
    Phoenix.PubSub.subscribe(Texttile.PubSub, @topic)
  end

  defp broadcast do
    Phoenix.PubSub.broadcast(Texttile.PubSub, @topic, {:newsletter_changed})
  end

  ## Joining

  @doc """
  A reader asks to be on the list. The address goes on it unconfirmed,
  and the confirmation link travels by mail; until the link is
  followed, the address gets no text. An address that already waits
  gets the same link again, so a lost mail is never a dead end - one
  link an hour, so the form is no way to mail a stranger over and
  over. A confirmed address is left in peace. `confirm_url:` builds
  the link from the token, and `now:` names the moment the one link an
  hour is measured from. It defaults to this one.
  """
  def join(email, opts) do
    confirm_url = Keyword.fetch!(opts, :confirm_url)
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now(:second) end)

    with {:ok, subscriber} <- ensure(email) do
      unless Subscriber.confirmed?(subscriber) do
        mail_confirmation(subscriber, confirm_url, now)
      end

      broadcast()
      {:ok, subscriber}
    end
  end

  @doc """
  An admin puts an address on the list, confirmed at once: the admin
  vouches for it, so no mail travels. An address that already waits
  for its reader is confirmed the same way.
  """
  def add(email) do
    with {:ok, subscriber} <- ensure(email) do
      subscriber = Confirmation.confirm(subscriber, DateTime.utc_now(:second))
      broadcast()
      {:ok, subscriber}
    end
  end

  defp ensure(email) do
    email = Subscriber.normalize(email)

    if Subscriber.address?(email) do
      {:ok,
       Repo.insert!(Subscriber.build(email),
         on_conflict: [set: [email: email]],
         conflict_target: :email,
         returning: true
       )}
    else
      {:error, :invalid}
    end
  end

  defp mail_confirmation(subscriber, confirm_url, now) do
    Confirmation.ask(
      subscriber,
      fn token -> Notifier.deliver_confirmation(subscriber, confirm_url.(token)) end,
      now
    )
  end

  ## Confirming and leaving

  @doc """
  The mailed link was followed: the address is confirmed and gets the
  texts from now on. A link works any number of times; an unknown
  token answers `:error`.
  """
  def confirm(token) when is_binary(token) do
    case Repo.get_by(Subscriber, token: token) do
      nil ->
        :error

      %Subscriber{} = subscriber ->
        subscriber = Confirmation.confirm(subscriber, DateTime.utc_now(:second))
        broadcast()
        {:ok, subscriber}
    end
  end

  @doc "The subscriber behind a token, or nil. Nothing changes."
  def by_token(token) when is_binary(token) do
    Repo.get_by(Subscriber, token: token)
  end

  @doc """
  The way off the list: the token's address goes, and the token with
  it. Always `:ok` - to the person leaving, a spent link and a followed
  one are the same thing.
  """
  def unsubscribe(token) when is_binary(token) do
    case Repo.delete_all(from s in Subscriber, where: s.token == ^token) do
      {1, _} -> broadcast()
      {0, _} -> :ok
    end

    :ok
  end

  @doc """
  The admin area takes an address off the list. An address another admin
  removed first answers `{:error, :gone}`.
  """
  def remove(id) do
    case Repo.get(Subscriber, id) do
      nil ->
        {:error, :gone}

      subscriber ->
        case Repo.delete_all(from s in Subscriber, where: s.id == ^subscriber.id) do
          {1, _} ->
            broadcast()
            {:ok, subscriber}

          {0, _} ->
            {:error, :gone}
        end
    end
  end

  ## Reading

  @doc "Everybody on the list, newest first, waiting addresses included."
  def list do
    from(s in Subscriber, order_by: [desc: s.id]) |> Repo.all()
  end

  @doc "The addresses the texts go to."
  def confirmed do
    from(s in Subscriber, where: not is_nil(s.confirmed_at), order_by: [desc: s.id])
    |> Repo.all()
  end

  @doc "How many addresses the texts go to."
  def confirmed_count do
    from(s in Subscriber, where: not is_nil(s.confirmed_at)) |> Repo.aggregate(:count)
  end

  ## The publish email

  @doc """
  A text went live this moment: the subscriber email goes out, once.
  The callers are the two go-live paths in `Texttile.Articles` and
  nobody else; they call only on the move to published, never on a
  date edit of a live text.

  The stamp is the lock. `notified_on` goes from empty to today in one
  statement, and only the caller whose statement wrote the row sends:
  the go-live clock and a publish click in the same second cannot both
  mail the list. The mails themselves leave in a watched task, because
  a publish click must not wait for another server. Pages, unchecked
  texts and already-stamped texts pass through untouched. Answers the
  text as it now stands.
  """
  def notify_published(
        %Article{status: "published", type: "post", notify_on_publish: true, notified_on: nil} =
          article
      ) do
    today = Date.utc_today()

    claimed =
      from(a in Article, where: a.id == ^article.id and is_nil(a.notified_on))
      |> Repo.update_all(set: [notified_on: today])

    case claimed do
      {1, _} ->
        article = %{article | notified_on: today}
        send_new_text(article)
        article

      {0, _} ->
        # somebody else went live with this text a moment ago and is
        # mailing it right now
        Repo.get(Article, article.id) || article
    end
  end

  def notify_published(%Article{} = article), do: article

  # The mail carries what the readers have, never the working copy: it
  # is the one reader whose copy cannot be taken back once it is out.
  defp send_new_text(article) do
    article = Reading.text(article, :reader)

    case confirmed() do
      [] ->
        :ok

      subscribers ->
        site = Settings.site_title()
        password = access_word()
        # Read here, where this process owns its database connection.
        # The task below owns none: nobody waits for it, so it may
        # outlive whoever started it.
        locale = Texttile.I18n.site_locale()

        {:ok, _pid} =
          Task.Supervisor.start_child(Texttile.Newsletter.TaskSupervisor, fn ->
            Texttile.I18n.put_locale(locale)

            Enum.each(subscribers, fn subscriber ->
              deliver_one(subscriber, article, site, password)
              # One pause after each address. Every mail provider counts
              # requests per second, and a list of 200 sent as fast as
              # the loop runs comes back as refusals for most of them.
              Process.sleep(pace_ms())
            end)
          end)

        :ok
    end
  end

  # A refused mail is the one thing this feature cannot repair by
  # itself: the text is stamped, so nothing sends it again. The least
  # it owes the person running the site is a line in the log. The
  # subscriber stands there as a number: a log travels further than a
  # database, and a reader's address has no business in it.
  defp deliver_one(subscriber, article, site, password) do
    case Notifier.deliver_new_text(subscriber, article, site, password) do
      {:ok, _email} ->
        :ok

      other ->
        Logger.error(
          "newsletter: #{Articles.display_title(article)} did not reach " <>
            "subscriber #{subscriber.id}: #{inspect(other)}"
        )
    end
  end

  defp pace_ms, do: Application.get_env(:texttile, :newsletter_pace_ms, 600)

  # The shared access word, while the blog asks for one. It goes into
  # the mail as plain text; that is what it is for (see
  # TexttileWeb.SiteGate).
  defp access_word do
    if Settings.guarded?(), do: Settings.get(:site_password)
  end
end
