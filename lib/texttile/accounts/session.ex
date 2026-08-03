defmodule Texttile.Accounts.Session do
  @moduledoc """
  One signed-in browser. The token lives in the session cookie; deleting
  the row signs that browser out.
  """

  use Ecto.Schema

  schema "sessions" do
    field :token, :binary
    belongs_to :user, Texttile.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @rand_size 32

  def build(user) do
    %__MODULE__{token: :crypto.strong_rand_bytes(@rand_size), user_id: user.id}
  end
end
