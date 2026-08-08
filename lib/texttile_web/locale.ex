defmodule TexttileWeb.Locale do
  @moduledoc """
  The site language, on every process that renders a page.

  Gettext holds the locale per process, and a page is rendered by two
  of them: the request process draws the first, dead HTML, and the
  LiveView process draws every render after it. So the language is put
  twice, by the plug and by the on_mount, and neither one can stand for
  the other.
  """

  alias Texttile.I18n

  def init(opts), do: opts

  def call(conn, _opts) do
    I18n.put_site_locale()
    conn
  end

  def on_mount(:put_locale, _params, _session, socket) do
    I18n.put_site_locale()
    {:cont, socket}
  end
end
