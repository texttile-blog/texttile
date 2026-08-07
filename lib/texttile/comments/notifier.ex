defmodule Texttile.Comments.Notifier do
  @moduledoc """
  The one mail a commenting reader can get: the link that confirms the
  address. One link per address; the mail may travel again with a later
  comment, but it always carries the same link.
  """

  import Swoosh.Email

  alias Texttile.Mailer
  alias Texttile.Settings

  @doc "Mails the confirmation link for the comment's address."
  def deliver_confirmation(comment, url) do
    site = Settings.site_title()
    title = Texttile.Articles.display_title(comment.article)

    email =
      new()
      |> to({comment.name, comment.address.email})
      |> from({site, Application.fetch_env!(:texttile, :mail_from)})
      |> subject("Confirm your email on #{site}")
      |> text_body("""
      Hello #{comment.name},

      You wrote a comment on "#{title}".

      Open this link, and your comment appears under the text:

      #{url}

      You confirm this address once. Every comment you write after
      that appears at once. If you did not write a comment on #{site},
      ignore this mail.
      """)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
