defmodule Texttile.Comments do
  @moduledoc """
  The readers' comments. One rule, one wording, everywhere: while the
  `comments_require_confirmation` setting is on, a comment waits for the
  reader's own email confirmation and readers do not see it; while it is
  off, every comment appears the moment it is sent. Nothing here is an
  approval queue - no admin ever lets a comment through, an admin only
  deletes.

  The reader confirms an address once. The link travels by mail, the
  address remembers it was followed, and every later comment from it
  appears at once. Every change is announced on the comments topic.
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

      broadcast({:comment_posted, comment})
      {:ok, comment}
    end
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
  confirmation, otherwise only once its address is confirmed. The one
  exception - the reader who just sent it sees their own - lives where
  the session is, in the web layer.
  """
  def shown_to_readers?(%Comment{} = comment) do
    not Settings.get(:comments_require_confirmation) or
      Address.confirmed?(comment.address)
  end

  @doc "`shown_to_readers?/1` with the setting read once for a whole list."
  def shown_to_readers?(%Comment{} = comment, require_confirmation?) do
    not require_confirmation? or Address.confirmed?(comment.address)
  end

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
          address
          |> Ecto.Changeset.change(confirmed_at: DateTime.utc_now(:second))
          |> Repo.update!()

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

  ## Reading and counting

  @doc "One comment, with its address."
  def get_comment!(id), do: Comment |> Repo.get!(id) |> Repo.preload(:address)

  @doc "One comment, with its address, or nil when it is already gone."
  def get_comment(id) do
    case Repo.get(Comment, id) do
      nil -> nil
      comment -> Repo.preload(comment, :address)
    end
  end

  @doc "Every comment of one text, newest first, addresses along."
  def for_article(article_id) do
    from(c in Comment,
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
      from(c in Comment,
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
    Repo.aggregate(from(c in Comment, where: c.article_id == ^article_id), :count)
  end

  @doc "The latest comments across all texts, newest first, texts along."
  def recent(limit) do
    from(c in Comment,
      order_by: [desc: c.id],
      limit: ^limit,
      preload: [:address, :article]
    )
    |> Repo.all()
  end

  @doc "How many comments the site holds, waiting ones included."
  def total_count, do: Repo.aggregate(Comment, :count)

  @doc """
  How many comments wait for their reader's confirmation - zero by
  definition while the setting does not ask for one.
  """
  def waiting_count do
    if Settings.get(:comments_require_confirmation) do
      from(c in Comment,
        join: a in assoc(c, :address),
        where: is_nil(a.confirmed_at)
      )
      |> Repo.aggregate(:count)
    else
      0
    end
  end

  @doc "Comment counts per text, one map, texts without comments absent."
  def count_map do
    from(c in Comment, group_by: c.article_id, select: {c.article_id, count(c.id)})
    |> Repo.all()
    |> Map.new()
  end

  ## Deleting

  @doc """
  Removes a comment, silently: no mail, no trace, announced on the topic.
  Takes the comment or its id. A comment another admin deleted first
  answers `{:error, :gone}`; two desks working the same list must not
  raise at each other.
  """
  def delete_comment(%Comment{} = comment) do
    case Repo.delete_all(from c in Comment, where: c.id == ^comment.id) do
      {1, _} ->
        broadcast({:comment_deleted, comment})
        {:ok, comment}

      {0, _} ->
        {:error, :gone}
    end
  end

  def delete_comment(id) do
    case get_comment(id) do
      nil -> {:error, :gone}
      comment -> delete_comment(comment)
    end
  end
end
