defmodule Texttile.Comments.Notifier do
  @moduledoc """
  The two mails a comment sends.

  The reader gets the link that confirms the address. One link per
  address; the mail may travel again with a later comment, but it
  always carries the same link.

  Everybody who runs the blog gets the comment itself, while
  `notify_on_comment` stands in the settings, and never before the
  comment stands under its text. The reader's address stays out of it:
  no screen of the admin area shows one either.
  """

  import Swoosh.Email

  require Logger

  alias Texttile.Accounts
  alias Texttile.Articles
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

  @doc """
  Mails the comment to everybody who runs the blog. Every account here
  carries an address, so every account gets one.
  """
  def deliver_to_admins(comment) do
    site = Settings.site_title()
    title = Articles.display_title(comment.article)
    body = admin_body(comment, site, title)

    Enum.each(Accounts.list_users(), &deliver_one(&1, site, "New comment on #{title}", body))
  end

  # A refused mail is nothing this can repair, and nothing the reader
  # who wrote the comment may ever hear about. The least it owes the
  # person running the site is a line in the log, the way the
  # newsletter writes one.
  defp deliver_one(user, site, subject, body) do
    email =
      new()
      |> to({Accounts.display_name(user), user.email})
      |> from({site, Application.fetch_env!(:texttile, :mail_from)})
      |> subject(subject)
      |> text_body(body)

    case Mailer.deliver(email) do
      {:ok, _metadata} -> :ok
      other -> Logger.error("comment mail did not reach account #{user.id}: #{inspect(other)}")
    end
  end

  defp admin_body(comment, site, title) do
    comments_url = TexttileWeb.Endpoint.url() <> "/admin/comments"

    """
    #{comment.name} wrote on "#{title}":

    #{comment.body}

    #{where_it_stands(comment.article)}    All comments:  #{comments_url}

    #{site} sends this mail because "Mail me every new comment" stands
    in its settings. Switch it off there to stop it.
    """
  end

  # A text that went off the site between the comment and the mail has
  # no address any more, and the mail says so instead of pointing
  # nowhere.
  defp where_it_stands(article) do
    case Articles.public_path(article) do
      nil ->
        "It is out of sight for now: the text itself is not on the site.\n\n"

      path ->
        "It stands under the text now.\n\n" <>
          "The text:      #{TexttileWeb.Endpoint.url()}#{path}\n"
    end
  end
end
