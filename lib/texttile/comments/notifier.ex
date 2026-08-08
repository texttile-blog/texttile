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

  Both write in the language of the process that calls them, and ask
  for none of their own. The admin mail leaves in a task, and a task
  nobody waits for owns no database connection, so its language is
  handed in where the task is started. See `Texttile.I18n`.
  """

  use Gettext, backend: TexttileWeb.Gettext

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
      |> subject(gettext("Confirm your email on %{site}", site: site))
      |> text_body(
        gettext(
          """
          Hello %{name},

          You wrote a comment on "%{title}".

          Open this link, and your comment appears under the entry:

          %{url}

          You confirm this address once. Every comment you write after
          that appears at once. If you did not write a comment on %{site},
          ignore this mail.
          """,
          name: comment.name,
          title: title,
          url: url,
          site: site
        )
      )

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Mails the comment to everybody who runs the blog. Every account here
  carries an address, so every account gets one - except the account
  that wrote the comment, which was there when it was written.
  """
  def deliver_to_admins(comment) do
    site = Settings.site_title()
    title = Articles.display_title(comment.article)
    body = admin_body(comment, site, title)

    Accounts.list_users()
    |> Enum.reject(&(&1.id == comment.user_id))
    |> Enum.each(&deliver_one(&1, site, gettext("New comment on %{title}", title: title), body))
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

    gettext(
      """
      %{name} wrote on "%{title}":

      %{body}

      %{where}    All comments:  %{url}

      %{site} sends this mail because "Mail me every new comment" stands
      in its settings. Switch it off there to stop it.
      """,
      name: comment.name,
      title: title,
      body: comment.body,
      where: where_it_stands(comment.article),
      url: comments_url,
      site: site
    )
  end

  # A text that went off the site between the comment and the mail has
  # no address any more, and the mail says so instead of pointing
  # nowhere.
  defp where_it_stands(article) do
    case Articles.public_path(article) do
      nil ->
        gettext("It is out of sight for now: the entry itself is not on the site.") <> "\n\n"

      path ->
        gettext("It stands under the entry now.") <>
          "\n\n" <>
          gettext("The entry:     %{url}", url: TexttileWeb.Endpoint.url() <> path) <> "\n"
    end
  end
end
