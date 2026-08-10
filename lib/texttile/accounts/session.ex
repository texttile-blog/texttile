defmodule Texttile.Accounts.Session do
  @moduledoc """
  One signed-in browser. The token lives in the cookie; deleting the row
  signs that browser out.

  `expires_at` is the moment the session ends, set at the sign-in and
  never moved: two days, or fourteen when the browser is remembered. The
  cookie carries the same span, so the two die together.
  """

  use Ecto.Schema

  schema "sessions" do
    field :token, :binary
    field :expires_at, :utc_datetime
    belongs_to :user, Texttile.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @rand_size 32

  def build(user, expires_at) do
    %__MODULE__{
      token: :crypto.strong_rand_bytes(@rand_size),
      user_id: user.id,
      expires_at: expires_at
    }
  end
end
