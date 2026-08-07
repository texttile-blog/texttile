defmodule Texttile.Newsletter.Notifier do
  @moduledoc """
  The two mails of the newsletter: the link that confirms an address,
  and the text that just went live. Both are plain text, both carry
  the same token - as the confirmation link in the first, as the way
  off the list in the second.

  The new-text mail may leave from the go-live clock, where no request
  stands behind it, so this module asks the endpoint for the site's
  address instead of taking a URL from a caller.
  """

  import Swoosh.Email

  alias Texttile.Articles
  alias Texttile.Mailer
  alias Texttile.Newsletter.Subscriber

  @doc "Mails the link that puts the address on the list."
  def deliver_confirmation(%Subscriber{} = subscriber, url) do
    site = Texttile.Settings.site_title()

    # The subject and the shape are the comment confirmation's, word for
    # word where they can be: this mail confirms an address, like that
    # one, and a mailbox that reads "Get ... by mail" reads an offer.
    deliver(
      subscriber.email,
      site,
      "Confirm your email on #{site}",
      """
      This address asked for the new texts of #{site} by mail.

      Open this link, and you are on the list:

      #{url}

      You confirm this address once. If you did not ask for this,
      ignore this mail. Without the link, the address gets nothing.
      """
    )
  end

  @doc """
  Mails one subscriber the text that just went live: the title, the
  first paragraph, the address it lives at - and the access word, while
  the blog asks for one.
  """
  def deliver_new_text(%Subscriber{} = subscriber, article, site, password) do
    title = Articles.display_title(article)
    url = TexttileWeb.Endpoint.url() <> Articles.public_path(article)

    unsubscribe_url =
      TexttileWeb.Endpoint.url() <> "/newsletter/unsubscribe/#{subscriber.token}"

    subscriber.email
    |> build(site, "New on #{site}: #{title}", """
    "#{title}" is now on #{site}:

    #{url}
    #{lead_block(article)}#{password_block(site, password)}
    You get this mail because this address is on the #{site} list.
    To leave the list, open this link:

    #{unsubscribe_url}
    """)
    # The way off the list, once more where the mail program itself
    # reads it: a mailbox that finds no List-Unsubscribe on mail that
    # goes to a list files it as the kind of mail nobody asked for.
    |> header("List-Unsubscribe", "<#{unsubscribe_url}>")
    |> send()
  end

  defp lead_block(article) do
    case Articles.lead(article) do
      "" -> ""
      lead -> "\n#{lead}\n"
    end
  end

  defp password_block(_site, nil), do: ""

  defp password_block(site, password) do
    """

    #{site} asks for its access word before it shows the text.
    The word is: #{password}
    """
  end

  defp deliver(to, site, subject, body) do
    to |> build(site, subject, body) |> send()
  end

  # The reader knows the site by its title, not by the product it runs
  # on, so the title is the sender name.
  defp build(to, site, subject, body) do
    new()
    |> to(to)
    |> from({site, Application.fetch_env!(:texttile, :mail_from)})
    |> subject(subject)
    |> text_body(body)
  end

  defp send(email) do
    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
