defmodule Texttile.Comments do
  @moduledoc """
  The readers' comments. One rule, one wording, everywhere: while the
  `comments_require_confirmation` setting is on, a comment waits for the
  reader's own email confirmation and readers do not see it; while it is
  off, every comment appears the moment it is sent.

  The reader confirms an address once. The link travels by mail, the
  address remembers it was followed, and every later comment from it
  appears at once.

  This is still not an approval queue: nothing waits for the desk, and
  the desk lets nothing through by default. What the desk can do is make
  one exception, one comment at a time - `release_comment/1` puts a
  single comment under the text while its address stays unconfirmed, so
  the next comment from that address waits like every other. It can also
  rewrite the words of a comment, and it deletes into a trash that keeps
  a comment for 30 days before the row goes for good.

  Every change is announced on the comments topic.
  """

  import Ecto.Query

  alias Texttile.Articles.Article
  alias Texttile.Comments.Address
  alias Texttile.Comments.Comment
  alias Texttile.Comments.Notifier
  alias Texttile.Repo
  alias Texttile.Settings

  @topic "comments"

  ## PubSub

  @doc """
  Subscribes the caller to `{:comment_posted, comment}`,
  `{:comment_deleted, comment}` and `{:comments_confirmed, address_id}`.
  """
  def subscribe do
    Phoenix.PubSub.subscribe(Texttile.PubSub, @topic)
  end

  defp broadcast(message) do
    Phoenix.PubSub.broadcast(Texttile.PubSub, @topic, message)
  end

  ## Posting

  @doc """
  Stores what a reader sent under a text: a name, an email, the words.

  Only a published text that allows comments takes one; everything else
  answers `{:error, :closed}`. The first comment from a fresh address
  gets the confirmation mail when the setting asks for one; an address
  that is still unconfirmed gets the same link again, so a lost mail is
  never a dead end. `confirm_url:` builds the link from the token.
  """
  def post(%Article{} = article, attrs, opts) do
    confirm_url = Keyword.fetch!(opts, :confirm_url)

    with :ok <- open_for_comments(article),
         {:ok, attrs} <- validate(attrs) do
      address = ensure_address(attrs)

      comment =
        %Comment{article_id: article.id, address_id: address.id}
        |> Comment.changeset(attrs)
        |> Repo.insert!()
        |> Map.put(:address, address)
        |> Map.put(:article, article)

      comment =
        if Settings.get(:comments_require_confirmation) and not Address.confirmed?(address) do
          Map.put(comment, :address, mail_confirmation(comment, address, confirm_url))
        else
          comment
        end

      if shown_to_readers?(comment), do: notify_admins(comment)
      broadcast({:comment_posted, comment})
      {:ok, comment}
    end
  end

  # The people who run the blog hear about a comment the moment it
  # stands under the text, and never before: while the reader has not
  # followed the link, nobody has proved that the address is theirs,
  # and the form would be a way to mail everybody here at will.
  #
  # The mail leaves in a task of its own, so the reader who wrote the
  # comment waits for this server and not for another one.
  defp notify_admins(comment) do
    if Settings.get(:notify_on_comment) do
      Task.Supervisor.start_child(Texttile.Comments.TaskSupervisor, fn ->
        Notifier.deliver_to_admins(comment)
      end)
    end

    :ok
  end

  # Nobody proves they own the address before the mail goes out, so the
  # address itself carries the limit: one link an hour. Without it the
  # form is a way to mail a stranger over and over, from the site's own
  # sending domain. The comment stands either way; the link is the same
  # one, and the next comment carries it again.
  @mail_interval_seconds 3600

  defp mail_confirmation(comment, address, confirm_url) do
    now = DateTime.utc_now(:second)

    if mailed_recently?(address, now) do
      address
    else
      Notifier.deliver_confirmation(comment, confirm_url.(address.token))

      address
      |> Ecto.Changeset.change(confirmation_mailed_at: now)
      |> Repo.update!()
    end
  end

  defp mailed_recently?(%Address{confirmation_mailed_at: nil}, _now), do: false

  defp mailed_recently?(%Address{confirmation_mailed_at: at}, now) do
    DateTime.diff(now, at) < @mail_interval_seconds
  end

  defp open_for_comments(%Article{status: "published", allow_comments: true}), do: :ok
  defp open_for_comments(%Article{}), do: {:error, :closed}

  defp validate(attrs) do
    changeset = Comment.post_changeset(%Comment{}, attrs)

    if changeset.valid? do
      {:ok, attrs}
    else
      {:error, %{changeset | action: :insert}}
    end
  end

  defp ensure_address(attrs) do
    email = Comment.normalize_email(Map.get(attrs, "email"))

    Repo.insert!(Address.build(email),
      on_conflict: [set: [email: email]],
      conflict_target: :email,
      returning: true
    )
  end

  ## What a reader sees

  @doc """
  Whether readers see the comment: yes while the setting asks for no
  confirmation, otherwise once its address is confirmed or the desk let
  this one comment through. The one exception - the reader who just sent
  it sees their own - lives where the session is, in the web layer.
  """
  def shown_to_readers?(%Comment{} = comment) do
    shown_to_readers?(comment, Settings.get(:comments_require_confirmation))
  end

  @doc "`shown_to_readers?/1` with the setting read once for a whole list."
  def shown_to_readers?(%Comment{} = comment, require_confirmation?) do
    not require_confirmation? or Address.confirmed?(comment.address) or released?(comment)
  end

  @doc "Whether the desk let this one comment through on its own."
  def released?(%Comment{released_at: released_at}), do: not is_nil(released_at)

  @doc "Whether the desk changed the words after the reader sent them."
  def edited?(%Comment{edited_at: edited_at}), do: not is_nil(edited_at)

  ## Confirming

  @doc """
  The mailed link was followed: the address is confirmed, every comment
  it wrote appears, and every later one appears at once. Answers the
  text of the address's newest comment, so the reader lands where their
  words now stand. A link works any number of times; an unknown token
  answers `:error`.
  """
  def confirm(token) when is_binary(token) do
    case Repo.get_by(Address, token: token) do
      nil ->
        :error

      %Address{} = address ->
        unless Address.confirmed?(address) do
          address =
            address
            |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now(:second))
            |> Repo.update!()

          # Everything this address wrote stands under its text from
          # this moment, so this is when the blog hears about it. Not
          # while the setting is off: the words were already under the
          # text when they arrived, and they travelled then.
          if Settings.get(:comments_require_confirmation) do
            Enum.each(waiting_of(address), &notify_admins/1)
          end

          broadcast({:comments_confirmed, address.id})
        end

        article =
          from(c in Comment,
            where: c.address_id == ^address.id,
            order_by: [desc: c.id],
            limit: 1,
            join: a in assoc(c, :article),
            select: a
          )
          |> Repo.one()

        {:ok, article}
    end
  end

  # Every comment of an address that has just been confirmed, with the
  # text it stands under and the address itself, the way the mail
  # needs them. A comment the desk already released is left out: it has
  # stood under the text since then, and it travelled then.
  defp waiting_of(%Address{} = address) do
    from(c in standing(), where: c.address_id == ^address.id and is_nil(c.released_at))
    |> order_by(asc: :id)
    |> Repo.all()
    |> Repo.preload(:article)
    |> Enum.map(&Map.put(&1, :address, address))
  end

  ## Reading and counting

  # Every comment except the ones in the trash. Nothing outside the
  # trash itself ever asks for those: to the desk and to the reader a
  # deleted comment is gone from the moment it is deleted.
  defp standing, do: from(c in Comment, where: is_nil(c.delete_after))

  @doc "One comment, with its address."
  def get_comment!(id), do: standing() |> Repo.get!(id) |> Repo.preload(:address)

  @doc "One comment, with its address, or nil when it is already gone."
  def get_comment(id) do
    case Repo.get(standing(), id) do
      nil -> nil
      comment -> Repo.preload(comment, :address)
    end
  end

  @doc "Every comment of one text, newest first, addresses along."
  def for_article(article_id) do
    from(c in standing(),
      where: c.article_id == ^article_id,
      order_by: [desc: c.id],
      preload: :address
    )
    |> Repo.all()
  end

  # How many comments one text ever puts into one reader's page. A blog
  # never reaches it; a text under attack does, and the page stays a
  # page instead of growing without an end.
  @reader_limit 200

  @doc """
  A text's comments the way its readers meet them, oldest first, so a
  conversation reads top to bottom. The newest #{@reader_limit} at most:
  answers the rows and how many older ones stayed out.
  """
  def for_readers(article_id) do
    newest =
      from(c in standing(),
        where: c.article_id == ^article_id,
        order_by: [desc: c.id],
        limit: ^@reader_limit,
        preload: :address
      )
      |> Repo.all()

    earlier =
      if length(newest) < @reader_limit do
        0
      else
        count_for(article_id) - length(newest)
      end

    {Enum.reverse(newest), earlier}
  end

  @doc "How many comments one text carries."
  def count_for(article_id) do
    Repo.aggregate(from(c in standing(), where: c.article_id == ^article_id), :count)
  end

  @doc "The latest comments across all texts, newest first, texts along."
  def recent(limit) do
    from(c in standing(),
      order_by: [desc: c.id],
      limit: ^limit,
      preload: [:address, :article]
    )
    |> Repo.all()
  end

  @doc "How many comments the site holds, waiting ones included."
  def total_count, do: Repo.aggregate(standing(), :count)

  @doc """
  How many comments wait for their reader's confirmation - zero by
  definition while the setting does not ask for one, and a comment the
  desk released waits for nobody.
  """
  def waiting_count do
    if Settings.get(:comments_require_confirmation) do
      from(c in standing(),
        join: a in assoc(c, :address),
        where: is_nil(a.confirmed_at) and is_nil(c.released_at)
      )
      |> Repo.aggregate(:count)
    else
      0
    end
  end

  @doc "Comment counts per text, one map, texts without comments absent."
  def count_map do
    from(c in standing(), group_by: c.article_id, select: {c.article_id, count(c.id)})
    |> Repo.all()
    |> Map.new()
  end

  ## What the desk does to one comment

  @doc """
  Rewrites the words of one comment. Only the words: the name and the
  address stay as the reader sent them, and the comment keeps the mark
  that says the desk changed it. Readers get the new words at once.

  Answers `{:error, :gone}` for a comment that is not there any more,
  and `{:error, changeset}` for words that are empty or too long.
  """
  def edit_comment(id, body) do
    case get_comment(id) do
      nil ->
        {:error, :gone}

      comment ->
        case comment |> Comment.edit_changeset(body) |> Repo.update() do
          {:ok, comment} ->
            broadcast({:comment_changed, comment})
            {:ok, comment}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Lets one comment through while its address is still unconfirmed: it
  stands under the text from now on, and nothing else changes. The
  address proved nothing, so the next comment from it waits again.

  Nobody is mailed about it - the desk is the one doing it.
  """
  def release_comment(id) do
    case get_comment(id) do
      nil ->
        {:error, :gone}

      comment ->
        comment =
          comment
          |> Ecto.Changeset.change(released_at: DateTime.utc_now(:second))
          |> Repo.update!()

        broadcast({:comment_changed, comment})
        {:ok, comment}
    end
  end

  ## The trash

  # How long a deleted comment can still be brought back.
  @trash_days 30

  @doc "How many days a deleted comment waits in the trash."
  def trash_days, do: @trash_days

  @doc """
  Deletes a comment into the trash: readers stop seeing it at once and
  it leaves every list on the desk, but the row waits #{@trash_days}
  days for a `restore_comment/1`. Silent as before - no mail, no trace
  for the reader - and announced on the topic. Takes the comment or its
  id. A comment another desk deleted first answers `{:error, :gone}`;
  two desks working the same list must not raise at each other.
  """
  def delete_comment(%Comment{} = comment), do: delete_comment(comment.id)

  def delete_comment(id) do
    delete_after = DateTime.add(DateTime.utc_now(:second), @trash_days, :day)

    case get_comment(id) do
      nil ->
        {:error, :gone}

      comment ->
        comment = comment |> Ecto.Changeset.change(delete_after: delete_after) |> Repo.update!()
        broadcast({:comment_deleted, comment})
        {:ok, comment}
    end
  end

  @doc """
  Brings a comment back out of the trash, exactly as it stood: the same
  words, the same address, and the same rule deciding who sees it. A
  comment that is not in the trash answers `{:error, :gone}`.
  """
  def restore_comment(id) do
    case Repo.one(from c in Comment, where: c.id == ^id and not is_nil(c.delete_after)) do
      nil ->
        {:error, :gone}

      comment ->
        comment =
          comment
          |> Ecto.Changeset.change(delete_after: nil)
          |> Repo.update!()
          |> Repo.preload([:address, :article])

        broadcast({:comment_changed, comment})
        {:ok, comment}
    end
  end

  @doc "What waits in the trash, the one deleted last on top."
  def trashed do
    from(c in Comment,
      where: not is_nil(c.delete_after),
      order_by: [desc: c.delete_after, desc: c.id],
      preload: [:address, :article]
    )
    |> Repo.all()
  end

  @doc "How many comments the trash holds."
  def trashed_count do
    Repo.aggregate(from(c in Comment, where: not is_nil(c.delete_after)), :count)
  end

  @doc """
  Makes the deletions final whose #{@trash_days} days have run out, and
  answers how many rows went. Runs on boot and on a clock of its own,
  see `Texttile.Comments.Sweeper`.
  """
  def sweep_due do
    now = DateTime.utc_now(:second)

    {count, _} =
      Repo.delete_all(
        from c in Comment, where: not is_nil(c.delete_after) and c.delete_after <= ^now
      )

    count
  end
end
