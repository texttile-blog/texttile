defmodule Texttile.Comments.Comment do
  @moduledoc """
  One reader's comment on one text: a name, the words, and the address
  it came from. Whether readers see it follows the address and the site
  setting, and `released_at` is the one exception the desk can make; see
  `Texttile.Comments`. `delete_after` is the trash, `edited_at` says the
  desk changed the words.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "comments" do
    field :name, :string
    field :body, :string
    field :delete_after, :utc_datetime
    field :released_at, :utc_datetime
    field :edited_at, :utc_datetime

    belongs_to :article, Texttile.Articles.Article
    belongs_to :address, Texttile.Comments.Address

    timestamps(type: :utc_datetime)
  end

  # How much one comment holds. The reader's form and the desk's field
  # both stop here, and the changesets are the ones that decide.
  @body_limit 4000

  @doc "How many characters one comment holds."
  def body_limit, do: @body_limit

  @doc "What the reader typed: the name and the words. The address is set apart."
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:name, :body])
    |> update_change(:name, &String.trim/1)
    |> update_change(:body, &String.trim/1)
    |> validate_required([:name, :body])
    |> validate_length(:name, max: 120)
    |> validate_length(:body, max: @body_limit)
  end

  @doc """
  The desk rewrote the words. The body and nothing else: the name and
  the address stay as the reader sent them.
  """
  def edit_changeset(comment, body) do
    # Trimmed before the cast, not after: the cast reads words that are
    # only spaces as nothing at all, and `update_change` would then trim
    # a nil. A field is one piece of text, and a caller who sends a list
    # or a map instead has sent nothing.
    comment
    |> cast(%{body: body |> words() |> String.trim()}, [:body])
    |> validate_required([:body])
    |> validate_length(:body, max: @body_limit)
    |> put_change(:edited_at, DateTime.utc_now(:second))
  end

  defp words(body) when is_binary(body), do: body
  defp words(_body), do: ""

  @doc "The changeset that also checks the email, for the form's errors."
  def post_changeset(comment, attrs) do
    comment
    |> changeset(attrs)
    |> validate_email(attrs)
  end

  # The email lives on the address row, but the form validates it here,
  # so one changeset carries every error the reader can make.
  defp validate_email(changeset, attrs) do
    email = attrs |> Map.get("email", "") |> to_string()

    cond do
      String.trim(email) == "" ->
        add_error(changeset, :email, "can't be blank")

      not Regex.match?(~r/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/, String.trim(email)) ->
        add_error(changeset, :email, "does not look like an address")

      true ->
        changeset
    end
  end

  @doc "The address the way it is stored: folded to one spelling."
  def normalize_email(email), do: email |> to_string() |> String.trim() |> String.downcase()
end
