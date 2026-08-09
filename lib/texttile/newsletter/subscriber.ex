defmodule Texttile.Newsletter.Subscriber do
  @moduledoc """
  One address on the newsletter list, and whether its owner confirmed
  it. The token is the path segment of both mailed links: the one that
  confirms the address, and the one that takes it off the list. One
  token per address, for its whole life on the list.
  """

  use Ecto.Schema

  schema "newsletter_subscribers" do
    field :email, :string
    field :token, :string
    field :confirmed_at, :utc_datetime
    field :confirmation_mailed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "A fresh row for an address that is not on the list yet."
  def build(email) do
    %__MODULE__{email: Texttile.Confirmation.normalize(email), token: Texttile.Confirmation.token()}
  end

  @doc "Whether the owner of the address followed the mailed link."
  defdelegate confirmed?(subscriber), to: Texttile.Confirmation

  @doc "The address the way it is stored: folded to one spelling."
  defdelegate normalize(email), to: Texttile.Confirmation

  @doc "Whether the string can be an email address at all."
  defdelegate address?(email), to: Texttile.Confirmation
end
