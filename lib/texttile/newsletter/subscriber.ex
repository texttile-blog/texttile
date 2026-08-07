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
    %__MODULE__{
      email: email,
      token: :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    }
  end

  @doc "Whether the owner of the address followed the mailed link."
  def confirmed?(%__MODULE__{confirmed_at: confirmed_at}), do: not is_nil(confirmed_at)

  @doc "The address the way it is stored: folded to one spelling."
  def normalize(email), do: email |> to_string() |> String.trim() |> String.downcase()

  @doc "Whether the string can be an email address at all."
  def address?(email), do: Regex.match?(~r/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/, email)
end
