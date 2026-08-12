defmodule TexttileWeb.E2E.NewsletterFlowTest do
  use TexttileWeb.E2E

  alias Texttile.Newsletter

  test "a reader joins by mail, the admin adds one by hand, a publish mails both, one leaves",
       %{conn: conn} do
    # Mails from the server processes land in this test process.

    # The reader subscribes in the Subscribe section and confirms by mail.
    conn
    |> open_page("/")
    |> assert_has("#subscribe", text: "You get an email when a new entry goes out")
    |> fill_in("Email for new entries", with: "christel@example.org")
    # the test types faster than a person; the time trap must not read
    # that as a script
    |> age_form(:newsletter)
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
    |> open("/admin/newsletter")
    |> assert_has("#newsletterSub", text: "1 email gets updates")
    |> assert_has("#subList", text: "christel@example.org")
    |> fill_in("Email", with: "jens@example.org")
    |> click_button("Add")
    |> assert_has("#subList", text: "jens@example.org")
    |> assert_has("#newsletterSub", text: "2 emails get updates")

    # A publish click sends the text to both.
    conn
    |> open("/admin/texts")
    |> click_button("New entry")
    |> fill_in("Title", with: "Harbor mornings")
    |> click_button("#stateBtn .main", "Publish")
    # the mail cannot be called back, so the click asks first and names
    # the number of people it would reach
    |> assert_has("#dialog", text: "Publish and email 2 subscribers?")
    |> click_button("#dialog-ok", "Publish and send")
    |> assert_has("#stateWord", text: "Published")
    |> assert_has("#state", text: "the mail is on its way")
    |> assert_has("#notifyOpt", text: "went out on")

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
end
