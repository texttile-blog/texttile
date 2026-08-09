defmodule Texttile.Confirmation do
  @moduledoc """
  Proving that an address belongs to whoever wrote it.

  Two places ask for it, and both used to carry the whole flow: the
  interval, the mailing, the stamp, the token, the folding and the
  reading of what an address is. Line for line, twice over, down to the
  same regular expression.

  The two tables stay apart on purpose. An address that commented and
  an address on the newsletter list have different lives: one is
  attached to words under a text and goes when they go, the other
  carries a place on a list and a way off it. What they share is the
  flow, and the flow is here.

    * fold the address to one spelling, so one person is one row
    * refuse what cannot be an address at all
    * hand out one token per row, for that row's whole life
    * mail the link at most once an hour, because nobody has proved
      anything yet and the form must not become a way to mail a
      stranger over and over
    * remember that the owner followed it

  Two adapters, so the seam is a real one: `Texttile.Comments.Address`
  and `Texttile.Newsletter.Subscriber`. Both are plain rows carrying
  `token`, `confirmed_at` and `confirmation_mailed_at`; nothing here
  knows which table it is writing.
  """

  alias Texttile.Repo

  # Nobody proves they own the address before the mail goes out, so the
  # address itself carries the limit: one link an hour.
  @interval_seconds 3600

  @doc "How long an address waits before a second link may go out."
  def interval_seconds, do: @interval_seconds

  @doc "The address the way it is stored: folded to one spelling."
  def normalize(email), do: email |> to_string() |> String.trim() |> String.downcase()

  @doc "Whether the string can be an email address at all."
  def address?(email), do: Regex.match?(~r/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/, to_string(email))

  @doc "A fresh token: the path segment of every link this address gets."
  def token, do: 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  @doc "Whether the owner of the address followed the mailed link."
  def confirmed?(%{confirmed_at: confirmed_at}), do: not is_nil(confirmed_at)

  @doc "Whether a link went out to this address inside the last hour."
  def mailed_recently?(%{confirmation_mailed_at: nil}, _now), do: false

  def mailed_recently?(%{confirmation_mailed_at: at}, now) do
    DateTime.diff(now, at) < @interval_seconds
  end

  @doc """
  Asks the owner to prove the address, unless a link went out inside
  the last hour. `deliver` is called with the token and builds and
  sends the mail. Answers the row, stamped when a link went out.
  """
  def ask(row, deliver, now) when is_function(deliver, 1) do
    if mailed_recently?(row, now) do
      row
    else
      deliver.(row.token)
      stamp(row, confirmation_mailed_at: now)
    end
  end

  @doc """
  The one place an address becomes a confirmed one, whichever way it
  got there: its owner followed the link, an admin vouched for it, or
  an account proved it at its first sign-in. Confirming twice leaves
  the first moment standing.
  """
  def confirm(row, now) do
    if confirmed?(row), do: row, else: stamp(row, confirmed_at: now)
  end

  defp stamp(row, changes), do: row |> Ecto.Changeset.change(changes) |> Repo.update!()
end
