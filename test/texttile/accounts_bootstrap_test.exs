defmodule Texttile.AccountsBootstrapTest do
  @moduledoc """
  What ADMIN_USERS does at the start of the server. The site is the
  thing that has to come up; the invitations run beside it.
  """
  use Texttile.DataCase, async: false

  import ExUnit.CaptureLog
  import Texttile.AccountsFixtures

  alias Texttile.Accounts
  alias Texttile.Accounts.Bootstrap

  test "invites the configured address and points the link at this server" do
    configure_admin_emails(["kb@example.org"])

    Bootstrap.run()

    assert Accounts.pending?(Accounts.get_user_by_email("kb@example.org"))
    assert_received {:email, email}
    assert email.text_body =~ TexttileWeb.Endpoint.url() <> "/link/"
  end

  # A blog answering its readers must not depend on a mail server or on
  # a variable full of typos, so anything that goes wrong here is
  # written into the log and left there.
  test "a start that goes wrong is a log line, not a stopped boot" do
    Application.put_env(:texttile, :admin_emails, [:not_an_address])

    log = capture_log(fn -> assert Bootstrap.run() == :ok end)

    assert log =~ "ADMIN_USERS could not be invited"
    assert Accounts.list_users() == []
  end
end
