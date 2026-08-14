defmodule Texttile.Articles.Article do
  @moduledoc """
  A text: the title and the Markdown body, the address it lives at, and
  the article settings. The body is a plain text buffer and stays one;
  every reading of it (rendering, the image panel, versions) derives
  from this column.

  `status` is one of draft, scheduled and published. A scheduled text
  carries a future `publish_date` and goes live on that day.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(draft scheduled published)
  @types ~w(post page)

  # The addresses the site itself answers on; no text may take them.
  @reserved_slugs ~w(admin login logout forgot link unlock blog tags
                     uploads renditions theme.css assets images dev)

  @doc "The slugs the public site keeps for its own routes."
  def reserved_slugs, do: @reserved_slugs

  schema "articles" do
    field :title, :string, default: ""
    field :body, :string, default: ""
    field :slug, :string
    field :status, :string, default: "draft"
    field :publish_date, :date
    field :type, :string, default: "post"
    field :tags, :string, default: ""
    field :allow_comments, :boolean, default: true
    field :notify_on_publish, :boolean, default: true
    field :notified_on, :date

    # The chosen preview image (uploads-relative). Nil lets the first
    # image of the text speak for it.
    field :preview_path, :string

    # Who the entry is by: whoever started it, until the Author field
    # in the editor names another account. The name beside the day on
    # the overviews and on the reader's page; nil where the account has
    # gone.
    belongs_to :user, Texttile.Accounts.User

    # The text the readers have. The title and the body above are the
    # working copy, which a live entry may run ahead of; this points at
    # the version a reader gets. Nil while the entry has never been
    # live. See `Texttile.Articles.Publishing`.
    belongs_to :live_version, Texttile.Articles.Version

    timestamps(type: :utc_datetime)
  end

  @doc "The autosave: the title and the body, nothing else."
  def text_changeset(article, attrs) do
    article
    |> cast(attrs, [:title, :body])
    |> validate_length(:title, max: 500)
  end

  @doc "The article settings; each field is atomic, last write wins."
  def settings_changeset(article, attrs) do
    article
    |> cast(attrs, [
      :type,
      :tags,
      :slug,
      :allow_comments,
      :notify_on_publish,
      :preview_path
    ])
    |> update_change(:slug, &normalize_slug/1)
    |> update_change(:tags, &normalize_tags/1)
    |> validate_inclusion(:type, @types)
    |> validate_exclusion(:slug, @reserved_slugs, message: "is an address the site itself uses")
    |> unique_constraint(:slug)
  end

  @doc """
  Who the entry is by. An entry is always somebody's, so the account
  has to be there; the field in the editor offers the accounts and
  nothing else.
  """
  def author_changeset(article, attrs) do
    article
    |> cast(attrs, [:user_id])
    |> validate_required(:user_id)
    |> assoc_constraint(:user)
  end

  @doc "A state move: publish, schedule, unpublish, go live."
  def state_changeset(article, attrs) do
    article
    |> cast(attrs, [:status, :publish_date, :slug, :notified_on])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:slug)
  end

  # The tag row as the field should have written it: split on the
  # commas, trimmed, empties dropped, every tag once with the spelling
  # it was first given. The field hands over what somebody typed, and
  # a trailing comma is what the completion leaves behind.
  defp normalize_tags(nil), do: ""

  defp normalize_tags(tags) do
    tags
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq_by(&String.downcase/1)
    |> Enum.join(", ")
  end

  defp normalize_slug(nil), do: nil

  defp normalize_slug(slug) do
    case Texttile.Articles.slugify(slug) do
      "" -> nil
      clean -> clean
    end
  end
end
