defmodule Texttile.Accounts.LoginLink do
  @moduledoc """
  One mailed set-a-password link: the invitation of a new admin and the
  password reset are the same mechanism. The mail carries the token; the
  table carries only its hash, so a copy of the database opens no
  accounts. A link is good for one use and for a day, and a fresh link
  replaces the earlier one.
  """

  use Ecto.Schema

  schema "login_links" do
    field :token_hash, :binary, redact: true
    belongs_to :user, Texttile.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @rand_size 32

  @doc "A fresh link for the user: the token for the mail, the row for the table."
  def build(user) do
    token = :crypto.strong_rand_bytes(@rand_size) |> Base.url_encode64(padding: false)
    {token, %__MODULE__{token_hash: hash(token), user_id: user.id}}
  end

  @doc "The stored hash of a mailed token."
  def hash(token), do: :crypto.hash(:sha256, token)
end
