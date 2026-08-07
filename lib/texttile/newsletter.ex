defmodule Texttile.Newsletter do
  @moduledoc """
  The newsletter list, and the one mail it exists for: when a text goes
  live with Email subscribers checked, every confirmed address gets it.

  Two ways onto the list. A reader joins through the form on the site
  and confirms by mail first - until then the address stands on the
  list but gets nothing. An admin adds an address at the desk, and that
  address is confirmed at once: the admin vouches for it. Every mail
  the list sends carries the way off it. Every change is announced on
  the newsletter topic.
  """

  import Ecto.Query

  alias Texttile.Articles.Article
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
  the link from the token.
  """
  def join(email, opts) do
    confirm_url = Keyword.fetch!(opts, :confirm_url)

    with {:ok, subscriber} <- ensure(email) do
      unless Subscriber.confirmed?(subscriber) do
        mail_confirmation(subscriber, confirm_url)
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
      subscriber =
        if Subscriber.confirmed?(subscriber) do
          subscriber
        else
          subscriber
          |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now(:second))
          |> Repo.update!()
        end

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

  @mail_interval_seconds 3600

  defp mail_confirmation(subscriber, confirm_url) do
    now = DateTime.utc_now(:second)

    if mailed_recently?(subscriber, now) do
      subscriber
    else
      Notifier.deliver_confirmation(subscriber, confirm_url.(subscriber.token))

      subscriber
      |> Ecto.Changeset.change(confirmation_mailed_at: now)
      |> Repo.update!()
    end
  end

  defp mailed_recently?(%Subscriber{confirmation_mailed_at: nil}, _now), do: false

  defp mailed_recently?(%Subscriber{confirmation_mailed_at: at}, now) do
    DateTime.diff(now, at) < @mail_interval_seconds
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
        subscriber =
          if Subscriber.confirmed?(subscriber) do
            subscriber
          else
            subscriber
            |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now(:second))
            |> Repo.update!()
          end

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
  The desk takes an address off the list. An address another admin
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

  The text is stamped `notified_on` first, in the caller's process, so
  a second go-live can never mail again; the mails themselves leave in
  a watched task, because a publish click must not wait for another
  server. Pages, unchecked texts and already-stamped texts pass
  through untouched. Answers the text as it now stands.
  """
  def notify_published(
        %Article{status: "published", type: "post", notify_on_publish: true, notified_on: nil} =
          article
      ) do
    subscribers = confirmed()

    {:ok, article} =
      article
      |> Article.state_changeset(%{notified_on: Date.utc_today()})
      |> Repo.update()

    unless subscribers == [] do
      site = Settings.site_title()
      password = access_word()

      {:ok, _pid} =
        Task.Supervisor.start_child(Texttile.Newsletter.TaskSupervisor, fn ->
          Enum.each(subscribers, &Notifier.deliver_new_text(&1, article, site, password))
        end)
    end

    article
  end

  def notify_published(%Article{} = article), do: article

  # The shared access word, while the blog asks for one. It goes into
  # the mail as plain text; that is what it is for (see
  # TexttileWeb.SiteGate).
  defp access_word do
    with "protected" <- Settings.get(:site_visibility),
         word when word != "" <- Settings.get(:site_password) do
      word
    else
      _ -> nil
    end
  end
end
