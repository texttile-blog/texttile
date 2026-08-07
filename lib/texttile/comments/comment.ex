defmodule Texttile.Comments.Comment do
  @moduledoc """
  One reader's comment on one text: a name, the words, and the address
  it came from. Whether readers see it is not a column; it follows the
  address and the site setting, see `Texttile.Comments`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "comments" do
    field :name, :string
    field :body, :string

    belongs_to :article, Texttile.Articles.Article
    belongs_to :address, Texttile.Comments.Address

    timestamps(type: :utc_datetime)
  end

  @doc "What the reader typed: the name and the words. The address is set apart."
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:name, :body])
    |> update_change(:name, &String.trim/1)
    |> update_change(:body, &String.trim/1)
    |> validate_required([:name, :body])
    |> validate_length(:name, max: 120)
    |> validate_length(:body, max: 4000)
  end

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
