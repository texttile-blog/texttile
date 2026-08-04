defmodule Texttile.Accounts.User do
  @moduledoc """
  An admin account. Every account is an admin and all admins are equal.

  The username is the identity everything hangs on: sign-in, sessions,
  presence. The displayed name is what people read; empty means the
  username stands in. The email address is where mail goes, never a
  sign-in identity.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @username_format ~r/^[a-z0-9._-]+$/
  @username_max 32

  schema "users" do
    field :username, :string
    field :display_name, :string
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  The account somebody creates at their first sign-in. The username
  comes from the configuration, not from the form. The password, the
  email address and the displayed name come from its owner, and this is
  the one moment to ask: the address is what a password reset needs,
  so an account never exists without one.
  """
  def claim_changeset(user, attrs) do
    user
    |> cast(attrs, [:username, :password, :email, :display_name])
    |> validate_username()
    |> validate_email()
    |> validate_length(:display_name, max: 80)
    |> validate_confirmation(:password, message: "does not match the password")
    |> validate_password()
  end

  @doc """
  Whether a name could be a username at all. The configuration asks this
  about every name it holds, so a typo there stays a typo instead of
  becoming a name nobody can sign in with.
  """
  def valid_username?(name) when is_binary(name) do
    String.length(name) <= @username_max and Regex.match?(@username_format, name)
  end

  def valid_username?(_name), do: false

  def username_changeset(user, attrs) do
    user
    |> cast(attrs, [:username])
    |> validate_username()
  end

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

  defp validate_username(changeset) do
    changeset
    |> update_change(:username, &normalize/1)
    |> validate_required([:username])
    |> validate_format(:username, @username_format,
      message: "only lower case letters, digits, dot, dash and underscore"
    )
    |> validate_length(:username, max: @username_max)
    |> unsafe_validate_unique(:username, Texttile.Repo, message: "is already taken")
    |> unique_constraint(:username, message: "is already taken")
  end

  defp validate_email(changeset) do
    changeset
    |> update_change(:email, &normalize/1)
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/,
      message: "must be an email address"
    )
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, Texttile.Repo, message: "is already in use")
    |> unique_constraint(:email, message: "is already in use")
  end

  defp normalize(nil), do: nil
  defp normalize(value), do: value |> String.trim() |> String.downcase()

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

  @doc "True when the password matches this user's hash."
  def valid_password?(%__MODULE__{password_hash: hash}, password)
      when is_binary(hash) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hash)
  end

  def valid_password?(_user, _password) do
    Bcrypt.no_user_verify()
    false
  end
end
