defmodule Texttile.Accounts.User do
  @moduledoc """
  An admin account. Every account is an admin and all admins are equal.

  An account carries two names for one person, and each says one thing.
  The email address is the identity: it is what you sign in with, and
  readers never see it. The displayed name is what readers see; while it
  is empty the part in front of the @ stands in.

  An account that was invited has no password yet. It exists, it cannot
  sign in, and the mailed link is what gives it a password.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :display_name, :string
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  The account an invitation opens: an address, and nothing else. The
  password comes from the mailed link, the displayed name from the
  profile.
  """
  def invite_changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_email()
  end

  @email_format ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/
  @email_max 160

  @doc """
  Whether this could be an email address at all. The configuration asks
  this about every address it holds, while the database is not up yet,
  so the question stays a question about the text.
  """
  def valid_email?(email) when is_binary(email) do
    String.length(email) <= @email_max and Regex.match?(@email_format, email)
  end

  def valid_email?(_email), do: false

  def display_name_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name], empty_values: [])
    |> validate_length(:display_name, max: 80)
  end

  def email_changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_email()
  end

  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_password()
  end

  @doc "The address as it is stored and compared: trimmed and lower case."
  def normalize_email(nil), do: nil
  def normalize_email(email), do: email |> String.trim() |> String.downcase()

  defp validate_email(changeset) do
    changeset
    |> update_change(:email, &normalize_email/1)
    |> validate_required([:email])
    |> validate_format(:email, @email_format, message: "must be an email address")
    |> validate_length(:email, max: @email_max)
    |> unsafe_validate_unique(:email, Texttile.Repo, message: "is already in use")
    |> unique_constraint(:email, message: "is already in use")
  end

  defp validate_password(changeset) do
    changeset
    |> validate_required([:password])
    |> validate_length(:password, min: 12, message: "use at least 12 characters")
    |> validate_length(:password, max: 72, count: :bytes)
    |> hash_password()
  end

  defp hash_password(changeset) do
    password = get_change(changeset, :password)

    if password && changeset.valid? do
      changeset
      |> put_change(:password_hash, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end

  @doc """
  True when the password matches this user's hash. An account that was
  invited and never set one has no hash, so nothing matches it.
  """
  def valid_password?(%__MODULE__{password_hash: hash}, password)
      when is_binary(hash) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hash)
  end

  def valid_password?(_user, _password) do
    Bcrypt.no_user_verify()
    false
  end
end
