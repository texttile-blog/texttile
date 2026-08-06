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
  @reserved_slugs ~w(desk login logout forgot link unlock texts about
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
    field :protected, :boolean, default: false
    field :notified_on, :date

    # The chosen preview image (uploads-relative). Nil lets the first
    # image of the text speak for it.
    field :preview_path, :string

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
      :protected,
      :preview_path
    ])
    |> update_change(:slug, &normalize_slug/1)
    |> validate_inclusion(:type, @types)
    |> validate_exclusion(:slug, @reserved_slugs, message: "is an address the site itself uses")
    |> unique_constraint(:slug)
  end

  @doc "A state move: publish, schedule, unpublish, go live."
  def state_changeset(article, attrs) do
    article
    |> cast(attrs, [:status, :publish_date, :slug, :notified_on])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:slug)
  end

  defp normalize_slug(nil), do: nil

  defp normalize_slug(slug) do
    case Texttile.Articles.slugify(slug) do
      "" -> nil
      clean -> clean
    end
  end
end
