defmodule Texttile.Comments.Comment do
  @moduledoc """
  One reader's comment on one text: a name, the words, and the address
  it came from. Whether readers see it follows the address and the site
  setting, and `released_at` is the one exception an admin can make; see
  `Texttile.Comments`. `delete_after` is the trash, `edited_at` says an
  admin changed the words.

  `user_id` is set while somebody wrote the comment signed in. The name
  and the address are still stored on the comment and the address row:
  the words stay as they were written, whatever the account does later.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "comments" do
    field :name, :string
    field :body, :string
    field :delete_after, :utc_datetime
    field :released_at, :utc_datetime
    field :edited_at, :utc_datetime
    # The address the author gave for themselves, from the form or out
    # of a bundle; the name over the comment links to it. `imported_at`
    # is set while the comment came out of a bundle, and only an import
    # fills that one in. See `Texttile.Comments`.
    field :website, :string
    field :imported_at, :utc_datetime

    belongs_to :article, Texttile.Articles.Article
    belongs_to :address, Texttile.Comments.Address
    # Set while somebody wrote the comment signed in; nil for a reader.
    belongs_to :user, Texttile.Accounts.User

    timestamps(type: :utc_datetime)
  end

  # How much one comment holds. The reader's form and the admin's field
  # both stop here, and the changesets are the ones that decide.
  @body_limit 4000
  @name_limit 120
  @website_limit 200

  @doc "How many characters one comment holds."
  def body_limit, do: @body_limit

  @doc "How long the name over a comment may be."
  def name_limit, do: @name_limit

  @doc """
  What the reader typed: the name, the words, and the website they
  gave for themselves. The address is set apart.
  """
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:name, :body, :website])
    |> update_change(:name, &plain_line/1)
    |> update_change(:body, &String.trim/1)
    |> update_change(:website, &address/1)
    |> validate_required([:name, :body])
    |> validate_length(:name, max: @name_limit)
    |> validate_length(:body, max: @body_limit)
    |> validate_length(:website, max: @website_limit)
    |> validate_website()
  end

  # The name is one line. It travels into the To of a mail, where a line
  # break would end the header and start whatever came after it, so the
  # break never gets that far. What holds the line today is the encoding
  # of a library two floors down; this holds it here, where the rule is.
  defp plain_line(name) when is_binary(name) do
    name |> String.replace(~r/[\x00-\x1f\x7f]/, "") |> String.trim()
  end

  defp plain_line(name), do: name

  # Nobody types a scheme. A bare `example.org` is what people mean by
  # a website, so it becomes one; whoever writes `http://` keeps it.
  defp address(website) when is_binary(website) do
    case String.trim(website) do
      "" -> nil
      "http://" <> _rest = written -> written
      "https://" <> _rest = written -> written
      bare -> if String.contains?(bare, "://"), do: bare, else: "https://" <> bare
    end
  end

  defp address(_website), do: nil

  # A website has to be one a browser can follow: http or https, and a
  # host with a dot in it. Anything else is a typo or a `javascript:`
  # line, and neither belongs under a name.
  defp validate_website(changeset) do
    case get_change(changeset, :website) do
      nil ->
        changeset

      website ->
        uri = URI.parse(website)
        host = to_string(uri.host)

        if uri.scheme in ["http", "https"] and String.contains?(host, ".") and
             not String.contains?(website, " ") do
          changeset
        else
          add_error(changeset, :website, "does not look like a website")
        end
    end
  end

  @doc """
  An admin rewrote the words. The body and nothing else: the name and
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

      not Texttile.Confirmation.address?(String.trim(email)) ->
        add_error(changeset, :email, "does not look like an address")

      true ->
        changeset
    end
  end

  @doc "The address the way it is stored: folded to one spelling."
  defdelegate normalize_email(email), to: Texttile.Confirmation, as: :normalize
end
