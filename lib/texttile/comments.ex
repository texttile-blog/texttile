defmodule Texttile.Comments do
  @moduledoc """
  The readers' comments. One rule, one wording, everywhere: while the
  `comments_require_confirmation` setting is on, a comment waits for the
  reader's own email confirmation and readers do not see it; while it is
  off, every comment appears the moment it is sent.

  The reader confirms an address once. The link travels by mail, the
  address remembers it was followed, and every later comment from it
  appears at once.

  This is still not an approval queue: nothing waits for an admin, and
  no comment needs one to appear. What an admin can do is make one
  exception at a time - `release_comment/1` puts a single comment under
  the text while its address stays unconfirmed, so the next comment from
  that address waits like every other. An admin can also rewrite the
  words of a comment, and a delete goes into a trash that keeps the
  comment for 30 days before the row goes for good.

  Every change is announced on the comments topic.
  """

  import Ecto.Query

  alias Texttile.Articles.Article
  alias Texttile.Articles.Visibility
  alias Texttile.Comments.Address
  alias Texttile.Confirmation
  alias Texttile.Comments.Comment
  alias Texttile.Comments.Notifier
  alias Texttile.Repo
  alias Texttile.Settings

  @topic "comments"

  ## PubSub

  @doc """
  Subscribes the caller to `{:comment_posted, comment}`,
  `{:comment_deleted, comment}`, `{:comments_confirmed, address_id}`
  and `{:comments_imported, article_id}`.
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

  `user:` names the account that wrote the comment while signed in. That
  account already proved the address at its first sign-in, so no
  confirmation mail goes out and the comment stands under the text at
  once: the address is confirmed here, the way the mailed link would
  have confirmed it.

  `now:` names the moment the one link an hour is measured from. It
  defaults to this one.
  """
  def post(%Article{} = article, attrs, opts) do
    confirm_url = Keyword.fetch!(opts, :confirm_url)
    user = Keyword.get(opts, :user)
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now(:second) end)

    with :ok <- open_for_comments(article),
         {:ok, attrs} <- validate(attrs) do
      address = ensure_address(attrs)
      address = if user, do: Confirmation.confirm(address, now), else: address

      comment =
        %Comment{article_id: article.id, address_id: address.id, user_id: user && user.id}
        |> Comment.changeset(attrs)
        |> Repo.insert!()
        |> Map.put(:address, address)
        |> Map.put(:article, article)

      comment =
        if Settings.get(:comments_require_confirmation) and not Address.confirmed?(address) do
          Map.put(comment, :address, mail_confirmation(comment, address, confirm_url, now))
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
      # Read here, where this process owns its database connection; the
      # task below owns none.
      locale = Texttile.I18n.site_locale()

      Task.Supervisor.start_child(Texttile.Comments.TaskSupervisor, fn ->
        Texttile.I18n.put_locale(locale)
        Notifier.deliver_to_admins(comment)
      end)
    end

    :ok
  end

  # The comment stands either way; the link is the same one, and the
  # next comment carries it again. See Texttile.Confirmation for why
  # one link an hour.
  defp mail_confirmation(comment, address, confirm_url, now) do
    Confirmation.ask(
      address,
      fn token -> Notifier.deliver_confirmation(comment, confirm_url.(token)) end,
      now
    )
  end

  defp open_for_comments(%Article{} = article) do
    if Visibility.open_for_comments?(article), do: :ok, else: {:error, :closed}
  end

  defp validate(attrs) do
    changeset = Comment.post_changeset(%Comment{}, attrs)

    if changeset.valid? do
      {:ok, attrs}
    else
      {:error, %{changeset | action: :insert}}
    end
  end

  defp ensure_address(attrs) when is_map(attrs) do
    attrs |> Map.get("email") |> ensure_address()
  end

  defp ensure_address(email) do
    email = Confirmation.normalize(email)

    Repo.insert!(Address.build(email),
      on_conflict: [set: [email: email]],
      conflict_target: :email,
      returning: true
    )
  end

  ## What an import brings

  # The address of an imported comment whose author left none. Nobody
  # reaches this row through the form: a domain without a dot is not
  # an address here, and `.invalid` is a real address nowhere.
  @imported_address "imported@invalid"

  @doc """
  The address an imported comment carries when its author left none.
  Nothing can be written to it, and the admin screens leave the name
  of such a comment unlinked because of it.
  """
  def placeholder_address, do: @imported_address

  @doc """
  Puts the comments of a bundle under `article`, in the order they
  arrive. What the last import wrote goes first, so importing the same
  bundle twice gives the same comments and not two of each. A comment
  a reader wrote here carries no import mark and stays.

  Every imported comment stands under the entry at once. It stood
  under the entry of the old blog, and its address counts as confirmed
  from here on, the way an admin vouching for it would: an import is
  an admin saying these words belong here.

  Runs inside the import's own transaction, and a comment that does
  not fit raises there, so the bundle rolls back whole.
  """
  def replace_imported(%Article{} = article, comments) do
    Repo.delete_all(
      from c in Comment, where: c.article_id == ^article.id and not is_nil(c.imported_at)
    )

    now = DateTime.utc_now(:second)
    stored = Enum.map(comments, &insert_imported(article, &1, now))

    broadcast({:comments_imported, article.id})
    stored
  end

  defp insert_imported(%Article{} = article, comment, now) do
    address =
      comment.email
      |> Kernel.||(@imported_address)
      |> ensure_address()
      |> Confirmation.confirm(now)

    Repo.insert!(%Comment{
      article_id: article.id,
      address_id: address.id,
      name: comment.author,
      body: comment.text,
      website: comment.website,
      imported_at: now,
      inserted_at: comment.at,
      updated_at: comment.at
    })
  end

  ## What a reader sees

  @doc """
  Whether readers see the comment: yes while the setting asks for no
  confirmation, otherwise once its address is confirmed or an admin let
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

  @doc """
  The other side of `shown_to_readers?/2`, for the admin screens: the
  comment is out of the text, and it is its own reader who has to act.
  """
  def waiting?(%Comment{} = comment, require_confirmation?) do
    not shown_to_readers?(comment, require_confirmation?)
  end

  @doc "Whether an admin let this one comment through on its own."
  def released?(%Comment{released_at: released_at}), do: not is_nil(released_at)

  @doc "Whether an admin changed the words after the reader sent them."
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
          address = Confirmation.confirm(address, DateTime.utc_now(:second))

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
  # needs them. A comment an admin already released is left out: it has
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
  # trash itself ever asks for those: to an admin and to a reader a
  # deleted comment is gone from the moment it is deleted.
  defp standing, do: from(c in Comment, where: is_nil(c.delete_after))

  @doc "One comment, with its address."
  def get_comment!(id), do: standing() |> Repo.get!(id) |> Repo.preload(:address)

  @doc "One comment, with its address, or nil when it is already gone."
  def get_comment(id) do
    with id when not is_nil(id) <- to_id(id),
         %Comment{} = comment <- Repo.get(standing(), id) do
      Repo.preload(comment, :address)
    else
      _ -> nil
    end
  end

  # An id arrives from a button on a screen, so it arrives as a string,
  # and a caller who sends a list or a map instead sends nothing at
  # all. The same rule as on the reader's form: read as nothing, never
  # a crash.
  defp to_id(id) when is_integer(id), do: id

  defp to_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp to_id(_id), do: nil

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
  definition while the setting does not ask for one, and a comment an
  admin released waits for nobody.
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

  @doc """
  The same map for the reader's side of the site: only the comments the
  rule shows to everybody. While the confirmation setting is on, a
  comment that still waits for its reader counts for nobody, so the
  number on a card is the number under the text.
  """
  def reader_count_map do
    query =
      if Settings.get(:comments_require_confirmation) do
        from(c in standing(),
          join: a in assoc(c, :address),
          where: not is_nil(a.confirmed_at) or not is_nil(c.released_at)
        )
      else
        standing()
      end

    from(c in query, group_by: c.article_id, select: {c.article_id, count(c.id)})
    |> Repo.all()
    |> Map.new()
  end

  ## What an admin does to one comment

  @doc """
  Rewrites the words of one comment. Only the words: the name and the
  address stay as the reader sent them, and the comment keeps the mark
  that says an admin changed it. Readers get the new words at once.

  Answers `{:error, :gone}` for a comment that is not there any more,
  and `{:error, changeset}` for words that are empty or too long.
  """
  def edit_comment(id, body) do
    case get_comment(id) do
      nil ->
        {:error, :gone}

      comment ->
        changeset = Comment.edit_changeset(comment, body)

        if changeset.valid? do
          write(comment, standing(), Enum.to_list(changeset.changes), :comment_changed)
        else
          {:error, %{changeset | action: :update}}
        end
    end
  end

  # One change to one comment, the way two admins survive each other: the
  # update names the row and the state it must still be in, and it
  # counts the rows it wrote. A row that went for good underneath - the
  # text was deleted, or the sweeper came - answers `{:error, :gone}`
  # like every other race here, instead of raising a stale entry at
  # whoever was slower.
  defp write(%Comment{} = comment, query, changes, message) do
    changes = Keyword.put(changes, :updated_at, DateTime.utc_now(:second))

    case Repo.update_all(from(c in query, where: c.id == ^comment.id), set: changes) do
      {1, _} ->
        comment = struct(comment, changes)
        broadcast({message, comment})
        {:ok, comment}

      {0, _} ->
        {:error, :gone}
    end
  end

  @doc """
  Lets one comment through while its address is still unconfirmed: it
  stands under the text from now on, and nothing else changes. The
  address proved nothing, so the next comment from it waits again.

  Nobody is mailed about it - the admin is the one doing it.
  """
  def release_comment(id) do
    case get_comment(id) do
      nil ->
        {:error, :gone}

      comment ->
        write(comment, standing(), [released_at: DateTime.utc_now(:second)], :comment_changed)
    end
  end

  ## The trash

  # How long a deleted comment can still be brought back.
  @trash_days 30

  @doc "How many days a deleted comment waits in the trash."
  def trash_days, do: @trash_days

  @doc "How many characters one comment holds."
  defdelegate body_limit, to: Comment

  @doc """
  Deletes a comment into the trash: readers stop seeing it at once and
  it leaves every list in the admin area, but the row waits #{@trash_days}
  days for a `restore_comment/1`. Silent as before - no mail, no trace
  for the reader - and announced on the topic. Takes the comment or its
  id. A comment another admin deleted first answers `{:error, :gone}`;
  two admins working the same list must not raise at each other.

  `now:` names the moment the #{@trash_days} days run from. It defaults
  to this one.
  """
  def delete_comment(comment_or_id, opts \\ [])

  def delete_comment(%Comment{} = comment, opts), do: delete_comment(comment.id, opts)

  def delete_comment(id, opts) do
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now(:second) end)
    delete_after = DateTime.add(now, @trash_days, :day)

    case get_comment(id) do
      nil -> {:error, :gone}
      comment -> write(comment, standing(), [delete_after: delete_after], :comment_deleted)
    end
  end

  @doc """
  Brings a comment back out of the trash, exactly as it stood: the same
  words, the same address, and the same rule deciding who sees it. A
  comment that is not in the trash answers `{:error, :gone}`.
  """
  def restore_comment(id) do
    with id when not is_nil(id) <- to_id(id),
         %Comment{} = comment <- Repo.one(from c in in_trash(), where: c.id == ^id) do
      case write(comment, in_trash(), [delete_after: nil], :comment_changed) do
        {:ok, comment} -> {:ok, Repo.preload(comment, [:address, :article])}
        {:error, :gone} -> {:error, :gone}
      end
    else
      _ -> {:error, :gone}
    end
  end

  defp in_trash, do: from(c in Comment, where: not is_nil(c.delete_after))

  # How many of the trash one screen carries. The rest is a line, the
  # way the recent list does it: the trash holds a spam wave for thirty
  # days, and the page has to stay a page.
  @trash_shown 8

  @doc """
  What waits in the trash, the one deleted last on top, the newest
  #{@trash_shown} at most: the rows and how many older ones stayed out.
  """
  def trashed do
    rows =
      from(c in in_trash(),
        order_by: [desc: c.delete_after, desc: c.id],
        limit: ^@trash_shown,
        preload: [:address, :article]
      )
      |> Repo.all()

    earlier = if length(rows) < @trash_shown, do: 0, else: trashed_count() - length(rows)

    {rows, earlier}
  end

  @doc "How many comments the trash holds."
  def trashed_count, do: Repo.aggregate(in_trash(), :count)

  @doc """
  Makes the deletions final whose #{@trash_days} days have run out at
  `now`, which defaults to this moment, and answers how many comments
  went. Runs on boot and on a clock of its own, see
  `Texttile.Comments.Sweeper`.

  For good means for good: an address whose last comment goes here has
  nothing left on this site, so its row goes too, and the reader's
  email leaves the database with the words it was attached to.
  """
  def sweep_due(now \\ DateTime.utc_now(:second)) do
    {count, _} = Repo.delete_all(from c in in_trash(), where: c.delete_after <= ^now)

    if count > 0, do: sweep_addresses(now)
    count
  end

  # An address is fresh for a while before its first comment stands
  # beside it: `ensure_address/1` writes the two rows one after the
  # other. A sweep that fell between them would take the address the
  # comment is about to point at, so a young address is left alone.
  defp sweep_addresses(now) do
    Repo.delete_all(
      from a in Address,
        as: :address,
        where:
          a.inserted_at < ^DateTime.add(now, -1, :day) and
            not exists(from c in Comment, where: c.address_id == parent_as(:address).id)
    )
  end
end
