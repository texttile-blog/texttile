defmodule Texttile.Accounts.UserNotifier do
  @moduledoc """
  Account mail: the confirmation of a fresh account and the link that
  sets a new password, each as HTML (`TexttileWeb.MailHTML`) and as
  plain text. Nothing in here ever contains a password.

  Mail leaves in the language of the site, like every other word the
  blog says. Nothing here asks for that language: it writes in the
  language of whoever calls it, which is a request, and the plug put it
  there. See `Texttile.I18n`.
  """

  use Gettext, backend: TexttileWeb.Gettext

  import Swoosh.Email

  alias Texttile.Mailer
  alias Texttile.Settings
  alias TexttileWeb.MailHTML

  @doc """
  Mails the link that sets a password. The account that never had one
  reads its invitation, every other account reads a password reset: one
  link, and the mail says which of the two arrived.
  """
  def deliver_password_link(user, url, site) do
    if Texttile.Accounts.pending?(user),
      do: deliver_invitation(user, url, site),
      else: deliver_password_reset(user, url, site)
  end

  @doc """
  The invitation of a new admin: the account is there, and this link
  gives it a password. Nobody types a password for anybody else.

  The blog stands at the top as its own address, not as its name: the
  invitation may be the first thing its reader hears of this site. Like
  every other address in the mail it stands alone on the line right
  under its sentence, so no mail program can read a comma or a full
  stop as part of it.
  """
  def deliver_invitation(user, url, site) do
    blog = TexttileWeb.Endpoint.url()

    deliver(
      user,
      gettext("Your admin account on %{site}", site: site),
      gettext(
        """
        Hello,

        You have an admin account on this blog:
        %{blog}

        Your email address is what you sign in with.

        Open this link and choose your password:
        %{url}

        The link works once, and for a week. Nobody else sets your password, and no mail from this site ever contains one. If you did not expect this, you can ignore this mail: without the link the account stays closed.
        """,
        url: url,
        blog: blog
      ),
      heading: gettext("Your admin account"),
      lines: [
        gettext(
          "You have an admin account on %{blog}. Your email address is what you sign in with.",
          blog: URI.parse(blog).host
        )
      ],
      button: {gettext("Choose your password"), url},
      small:
        gettext(
          "The link works once, and for a week. Nobody else sets your password, and no mail from this site ever contains one. If you did not expect this, you can ignore this mail: without the link the account stays closed."
        )
    )
  end

  @doc """
  Mails a password reset: the link where the owner sets a new password
  themselves.
  """
  def deliver_password_reset(user, url, site) do
    name = Texttile.Accounts.display_name(user)

    deliver(
      user,
      gettext("Set a new password on %{site}", site: site),
      gettext(
        """
        Hello %{name},

        Somebody asked for a password reset for your account on %{site}.

        Open this link and set a new password:
        %{url}

        The link works once and for 24 hours. The old password works until you set the new one. If you did not ask for this, you can ignore this mail.
        """,
        name: name,
        site: site,
        url: url
      ),
      heading: gettext("Hello %{name},", name: name),
      lines: [
        gettext("Somebody asked for a password reset for your account on %{site}.", site: site)
      ],
      button: {gettext("Set a new password"), url},
      small:
        gettext(
          "The link works once and for 24 hours. The old password works until you set the new one. If you did not ask for this, you can ignore this mail."
        )
    )
  end

  # The reader knows the site by its title, not by the product it runs
  # on, so the title is the sender name. `html` is what the layout
  # needs beyond the site, the colours and the subject.
  defp deliver(user, subject, body, html) do
    site = Settings.site_title()

    email =
      new()
      |> to({Texttile.Accounts.display_name(user), user.email})
      |> from({site, Application.fetch_env!(:texttile, :mail_from)})
      |> subject(subject)
      |> text_body(body)
      |> html_body(
        MailHTML.render([site: site, colors: Settings.button_colors(), subject: subject] ++ html)
      )

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
