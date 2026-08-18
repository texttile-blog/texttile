defmodule Texttile.Accounts.Session do
  @moduledoc """
  One signed-in browser. The token lives in the cookie; deleting the row
  signs that browser out.

  The table carries only the hash of the token, the way the login links
  do. The database travels: the backup API hands it to a machine in the
  house, and `make db-pull` puts a copy on a laptop. A copy that held
  the tokens themselves would hold every open sign-in with it.

  `expires_at` is the moment the session ends, set at the sign-in and
  never moved: two days, or fourteen when the browser is remembered. The
  cookie carries the same span, so the two die together.
  """

  use Ecto.Schema

  schema "sessions" do
    field :token_hash, :binary, redact: true
    field :expires_at, :utc_datetime
    belongs_to :user, Texttile.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @rand_size 32

  @doc "A fresh session: the token for the cookie, the row for the table."
  def build(user, expires_at) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {token,
     %__MODULE__{
       token_hash: hash(token),
       user_id: user.id,
       expires_at: expires_at
     }}
  end

  @doc "The stored hash of a token from a cookie."
  def hash(token), do: :crypto.hash(:sha256, token)
end
