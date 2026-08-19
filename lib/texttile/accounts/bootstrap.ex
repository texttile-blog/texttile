defmodule Texttile.Accounts.Bootstrap do
  @moduledoc """
  What ADMIN_USERS does at the start of the server: an address in it
  that has no account gets one, and a mailed link that sets its
  password. See `Texttile.Accounts.invite_configured/1`.

  This runs beside the site, never in front of it. A mail server that
  is down, or a variable full of typos, must not stop a blog from
  answering its readers, so anything that goes wrong here is written
  into the log and left there.
  """

  use Task, restart: :temporary

  require Logger

  alias Texttile.Accounts

  def start_link(_opts), do: Task.start_link(__MODULE__, :run, [])

  def run do
    # Mail leaves in the language of the site, and a task that nobody
    # started from a request owns no locale of its own. See
    # `Texttile.I18n`.
    Texttile.I18n.put_site_locale()

    Accounts.invite_configured(
      site: TexttileWeb.Endpoint.host(),
      link_url: &(TexttileWeb.Endpoint.url() <> "/link/#{&1}")
    )
  rescue
    error ->
      Logger.error("""
      ADMIN_USERS could not be invited: #{Exception.message(error)}

      The site is up. Fix the mail configuration and start again, or \
      invite the address from Settings.\
      """)
  end
end
