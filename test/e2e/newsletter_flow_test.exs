defmodule TexttileWeb.E2E.NewsletterFlowTest do
  use TexttileWeb.E2E

  alias Texttile.Newsletter

  # The card of the newsletter pages stands in the middle of the page:
  # the same room to its left and to its right, measured on `main`,
  # because `body.site > main` is a flex column that turns
  # `justify-center` into vertical centring and would leave the card
  # against the left edge.
  @card_in_room """
  () => {
    const main = document.querySelector("main")
    const card = main.firstElementChild.getBoundingClientRect()
    const mb = main.getBoundingClientRect(), ms = getComputedStyle(main)
    return Math.abs((card.left - (mb.left + parseFloat(ms.paddingLeft))) -
                    ((mb.right - parseFloat(ms.paddingRight)) - card.right))
  }
  """

  test "a reader joins by mail, the admin adds one by hand, a publish mails both, one leaves",
       %{conn: conn} do
    # Mails from the server processes land in this test process.

    # The reader subscribes in the Subscribe section and confirms by mail.
    conn
    |> open_page("/")
    |> assert(contain_text(by_css("#subscribe"), "New entries by email, nothing else."))
    |> fill(by_label("Email for new entries"), "christel@example.org")
    # the test types faster than a person; the time trap must not read
    # that as a script
    |> age_form(:newsletter)
    |> click(by_role(:button, name: "Subscribe"))
    |> assert(contain_text(by_css("main"), "Now check your mail."))

    assert_receive {:email, %Swoosh.Email{} = mail}, 2000
    assert mail.to == [{"", "christel@example.org"}]
    [link] = Regex.run(~r"http://[^\s]+/newsletter/confirm/[^\s]+", mail.text_body)

    conn
    |> visit(link)
    |> assert(contain_text(by_css("main"), "You are on the list."))

    # The admin area: the list carries the reader, and the admin adds an
    # address by hand, confirmed at once.
    conn
    |> sign_in()
    |> open("/admin/newsletter")
    |> assert(contain_text(by_css("#newsletterSub"), "1"))
    |> assert(contain_text(by_css("#subList"), "christel@example.org"))
    |> fill(by_label("Email address"), "jens@example.org")
    |> click(by_role(:button, name: "Add subscriber"))
    |> assert(contain_text(by_css("#subList"), "jens@example.org"))
    |> assert(contain_text(by_css("#newsletterSub"), "2"))

    # A publish click sends the text to both.
    conn
    |> open("/admin/texts")
    |> click(by_role(:button, name: "New entry"))
    |> fill(by_label("Title", exact: true), "Harbor mornings")
    |> click(by_css("#stateBtn .main") |> filter(has_text: "Publish"))
    # the mail cannot be called back, so the click asks first and names
    # the number of people it would reach
    |> assert(contain_text(by_css("#dialog"), "Publish and email 2 subscribers?"))
    |> click(by_css("#dialog-ok"))
    |> assert(text(by_css("#stateWord"), "Live"))
    |> assert(contain_text(by_css("#toast"), "the mail is on its way"))
    |> assert(contain_text(by_css("#notifyOpt"), "went out on"))

    mails =
      for _ <- 1..2 do
        assert_receive {:email, %Swoosh.Email{subject: "Harbor mornings"} = mail},
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
    |> assert(contain_text(by_css("main"), "Leave the list?"))
    |> assert_script(@card_in_room, &assert(&1 < 1.5))
    |> click(by_role(:button, name: "Take me off the list"))
    |> assert(contain_text(by_css("main"), "You are off the list."))

    assert [%{email: "jens@example.org"}] = Newsletter.list()
  end
end
