defmodule TexttileWeb.E2E.NewsletterFlowTest do
  # Not async: SQLite serializes writers, concurrent sandbox owners flake.
  use PhoenixTest.Playwright.Case, async: false

  import Texttile.AccountsFixtures

  alias Texttile.Newsletter

  @moduletag :e2e

  setup {TexttileWeb.E2E, :close_browser_context_afterwards}

  # Every test in the run knocks from the same address, so the browser
  # must not meet a limit another test spent.
  setup do
    Texttile.RateLimiter.reset()
    :ok
  end

  test "a reader joins by mail, the admin adds one by hand, a publish mails both, one leaves",
       %{conn: conn} do
    user_fixture(%{username: "kb"})

    # Mails from the server processes land in this test process.
    Application.put_env(:swoosh, :shared_test_process, self())
    on_exit(fn -> Application.delete_env(:swoosh, :shared_test_process) end)

    # The reader subscribes in the Subscribe section and confirms by mail.
    conn
    |> visit("/")
    |> assert_has("#subscribe", text: "One email when a new text goes out")
    |> fill_in("Email for new texts", with: "christel@example.org")
    |> click_button("Subscribe")
    |> assert_has("main", text: "Now check your mail.")

    assert_receive {:email, %Swoosh.Email{} = mail}, 2000
    assert mail.to == [{"", "christel@example.org"}]
    [link] = Regex.run(~r"http://[^\s]+/newsletter/confirm/[^\s]+", mail.text_body)

    conn
    |> visit(link)
    |> assert_has("main", text: "You are on the list.")

    # The admin area: the list carries the reader, and the admin adds an
    # address by hand, confirmed at once.
    conn
    |> sign_in()
    |> visit("/admin/newsletter")
    |> assert_has("#newsletterSub", text: "1 address gets the texts")
    |> assert_has("#subList", text: "christel@example.org")
    |> fill_in("Email", with: "jens@example.org")
    |> click_button("Add")
    |> assert_has("#subList", text: "jens@example.org")
    |> assert_has("#newsletterSub", text: "2 addresses get the texts")

    # A publish click sends the text to both.
    conn
    |> visit("/admin")
    |> click_button("New text")
    |> fill_in("Title", with: "Harbor mornings")
    |> click_button("#stateBtn .main", "Publish")
    |> assert_has("#stamp", text: "published")
    |> assert_has("#state", text: "on its way to 2 subscribers")

    mails =
      for _ <- 1..2 do
        assert_receive {:email,
                        %Swoosh.Email{subject: "New on Texttile: Harbor mornings"} = mail},
                       2000

        mail
      end

    assert Enum.sort(Enum.map(mails, &elem(hd(&1.to), 1))) ==
             ["christel@example.org", "jens@example.org"]

    # One of them leaves through the mailed link: a page, one button.
    reader = Enum.find(mails, &(elem(hd(&1.to), 1) == "christel@example.org"))
    [leave] = Regex.run(~r"http://[^\s]+/newsletter/unsubscribe/[^\s]+", reader.text_body)

    conn
    |> visit(leave)
    |> assert_has("main", text: "Leave the list?")
    |> click_button("Take me off the list")
    |> assert_has("main", text: "You are off the list.")

    assert [%{email: "jens@example.org"}] = Newsletter.list()
  end

  defp sign_in(conn) do
    conn
    |> visit("/login")
    |> fill_in("Username", with: "kb")
    |> fill_in("Password", with: valid_password())
    |> click_button("Sign in")
    |> assert_has("#crumb", text: "Texts")
  end
end
