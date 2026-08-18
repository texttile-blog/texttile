defmodule Texttile.Accounts.UserNotifier do
  @moduledoc """
  Account mail: the confirmation of a fresh account and the link that
  sets a new password. Nothing in here ever contains a password.

  Mail leaves in the language of the site, like every other word the
  blog says. Nothing here asks for that language: it writes in the
  language of whoever calls it, which is a request, and the plug put it
  there. See `Texttile.I18n`.
  """

  use Gettext, backend: TexttileWeb.Gettext

  import Swoosh.Email

  alias Texttile.Mailer
  alias Texttile.Settings

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
  """
  def deliver_invitation(user, url, site) do
    deliver(
      user,
      gettext("Your admin account on %{site}", site: site),
      gettext(
        """
        Hello,

        You have an admin account on %{site}. This address is what you
        sign in with.

        Open this link and choose your password:

        %{url}

        The link works once, and for a week. Nobody else sets your
        password, and no mail from this site ever contains one. If you
        did not expect this, you can ignore this mail: without the link
        the account stays closed.
        """,
        site: site,
        url: url
      )
    )
  end

  @doc """
  Mails a password reset: the link where the owner sets a new password
  themselves.
  """
  def deliver_password_reset(user, url, site) do
    deliver(
      user,
      gettext("Set a new password on %{site}", site: site),
      gettext(
        """
        Hello %{name},

        Somebody asked for a password reset for your account on %{site}.

        Open this link and set a new password:

        %{url}

        The link works once and for 24 hours. The old password works until
        you set the new one. If you did not ask for this, you can ignore
        this mail.
        """,
        name: Texttile.Accounts.display_name(user),
        site: site,
        url: url
      )
    )
  end

  # The reader knows the site by its title, not by the product it runs
  # on, so the title is the sender name.
  defp deliver(user, subject, body) do
    email =
      new()
      |> to({Texttile.Accounts.display_name(user), user.email})
      |> from({Settings.site_title(), Application.fetch_env!(:texttile, :mail_from)})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end
end
