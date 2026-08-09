defmodule Texttile.Comments.Address do
  @moduledoc """
  One address that commented, and whether its owner confirmed it. The
  token is the confirmation link's path segment; one token per address,
  so the reader confirms once and every later comment appears at once.
  Never published anywhere a reader can see.
  """

  use Ecto.Schema

  schema "comment_addresses" do
    field :email, :string
    field :token, :string
    field :confirmed_at, :utc_datetime
    field :confirmation_mailed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "A fresh row for an email nobody has commented with yet."
  def build(email) do
    %__MODULE__{email: Texttile.Confirmation.normalize(email), token: Texttile.Confirmation.token()}
  end

  @doc "Whether the owner of the address followed the mailed link."
  defdelegate confirmed?(address), to: Texttile.Confirmation
end
