defmodule TexttileWeb.E2E.CommentsFlowTest do
  use TexttileWeb.E2E

  alias Texttile.Articles

  test "a reader comments, confirms by mail, the admin reads and deletes", %{conn: conn} do
    article = published_post(title: "Harbor mornings", body: "Fog over the pier.")

    # Mails from the server processes land in this test process.

    # The reader writes. The comment waits, visible only to its reader.
    conn
    |> open_page(Articles.public_path(article))
    |> assert(contain_text(by_css("#comments"), "Post a comment"))
    |> refute_has(by_css("#comment-count"))
    |> fill(by_label("Name"), "Grandma Christel")
    |> fill(by_css("#comment-email"), "christel@example.org")
    |> fill(by_label("Comment", exact: true), "More of the dog, please.")
    # no age_form here: this one send goes the way a reader's does, the
    # page's script draws the stamp and holds the send until the time
    # trap is satisfied
    |> click(by_role(:button, name: "Post comment"))
    |> assert(contain_text(by_css("#comment-note"), "Sent. Follow the link in your mail"),
      timeout: 8000
    )
    |> assert(contain_text(by_css("#comments"), "waiting for your confirmation"))

    # The mailed link publishes the comment for everybody.
    assert_receive {:email, %Swoosh.Email{} = mail}, 2000
    assert mail.to == [{"Grandma Christel", "christel@example.org"}]
    [link] = Regex.run(~r"http://[^\s]+/comments/confirm/[^\s]+", mail.text_body)

    conn
    |> visit(link)
    |> assert_has(by_css("#comments h2") |> filter(has_text: "1 comment"))
    |> assert(contain_text(by_css("#comments"), "More of the dog, please."))
    # the server writes the day, the browser adds the hour in its zone
    |> assert(contain_text(by_css("#comments time"), " at "))
    |> refute_has(by_css("#comments .wait"))

    # The admin area: the overview carries it, its jump opens the
    # text's tab, Delete takes it out.
    conn
    |> sign_in()
    |> open("/admin/comments")
    # nothing waits any more, so the filter for it leaves the row
    |> refute_has(by_css("#commentFilter a[data-f='waiting']"))
    |> assert(contain_text(by_css("#commentsList"), "Grandma Christel"))
    |> click(by_role(:link, name: "Harbor mornings"))
    |> assert(contain_text(by_css("#tp-comments"), "More of the dog, please."))
    |> click(by_role(:button, name: "Delete"))
    |> assert(contain_text(by_css("#dialog"), "Delete the comment of Grandma Christel?"))
    |> click(by_role(:button, name: "Delete the comment"))
    |> assert(contain_text(by_css("#tp-comments"), "No comments yet."))

    assert Texttile.Comments.status_counts()["all"] == 0
  end

  test "an admin releases one comment, rewrites it, trashes it and takes it back", %{conn: conn} do
    article = published_post(title: "Harbor mornings", body: "Fog over the pier.")

    # A reader wrote and never touched the mail. The form itself is the
    # test above; this one starts where that one ends, and it knocks on
    # nothing, so it never spends the rate limit a browser test running
    # beside it is about to need.
    {:ok, _} =
      Texttile.Comments.post(
        article,
        %{
          "name" => "Grandma Christel",
          "email" => "christel@example.org",
          "body" => "More of the dog, please."
        },
        confirm_url: &"http://localhost/comments/confirm/#{&1}"
      )

    # Nobody sees it while it waits, not even the count.
    session =
      conn
      |> open_page(Articles.public_path(article))
      |> refute_has(by_css("#comments") |> filter(has_text: "More of the dog, please."))
      |> refute_has(by_css("#comment-count"))

    # The admin lets this one comment through, and the text carries it.
    session =
      session
      |> sign_in()
      |> open("/admin/comments")
      |> assert(contain_text(by_css("#commentsList"), "unconfirmed"))
      |> click(by_role(:button, name: "Approve"))
      |> assert(contain_text(by_css("#commentsList"), "let through"))
      |> refute_has(by_css("#commentsList .wait"))
      |> open_page(Articles.public_path(article))
      |> assert(contain_text(by_css("#comment-count"), "1 comment"))
      |> refute_has(by_css("#comments") |> filter(has_text: "waiting for your confirmation"))

    # And rewrites the words the reader sent.
    session =
      session
      |> open("/admin/comments")
      |> click(by_role(:button, name: "Edit"))
      |> fill(by_label("The words of the comment"), "Less of the dog, please.")
      |> click(by_role(:button, name: "Save"))
      |> assert(contain_text(by_css("#commentsList"), "Less of the dog, please."))
      |> assert(contain_text(by_css("#commentsList"), "edited"))
      |> open_page(Articles.public_path(article))
      |> assert(contain_text(by_css("#comments"), "Less of the dog, please."))
      |> refute_has(by_css("#comments") |> filter(has_text: "More of the dog, please."))

    # Delete is the trash now: out of the text, kept in the admin area.
    session =
      session
      |> open("/admin/comments")
      |> click(by_css("#commentsList button") |> filter(has_text: "Delete"))
      |> click(by_role(:button, name: "Delete the comment"))
      |> refute_has(by_css("#commentsList") |> filter(has_text: "Less of the dog, please."))
      |> open_page(Articles.public_path(article))
      |> refute_has(by_css("#comments") |> filter(has_text: "Less of the dog, please."))

    # And the way back puts it exactly where it stood.
    session
    |> open("/admin/comments")
    |> click(by_css("#commentFilter a[data-f='trash']") |> filter(has_text: "Trash"))
    |> assert(contain_text(by_css("#commentsList"), "Less of the dog, please."))
    |> assert(contain_text(by_css("#commentsList"), "goes for good"))
    |> click(by_css("#commentsList button") |> filter(has_text: "Restore"))
    |> assert(contain_text(by_css("#commentsList"), "No comments here."))
    |> open_page(Articles.public_path(article))
    |> assert(contain_text(by_css("#comment-count"), "1 comment"))
    |> assert(contain_text(by_css("#comments"), "Less of the dog, please."))

    assert Texttile.Comments.status_counts()["all"] == 1
    assert Texttile.Comments.status_counts()["trash"] == 0
  end

  @tag Playwright.Test.use(viewport: %{width: 390, height: 844})
  test "a step of the pager lands on the top of the next comments", %{conn: conn} do
    article = published_post()

    # two full pages: a short second one would pull the scroll up by itself
    Texttile.CommentsFixtures.wave!(article, 50)

    conn
    |> sign_in()
    |> open("/admin/comments?status=waiting")
    |> run_script("() => window.scrollTo(0, document.body.scrollHeight)")
    |> click(by_css("#next-page"))
    |> assert(contain_text(by_css("#commentsList"), "Words 25"))
    # LiveView jumps to the anchor a frame after the new rows are in, so
    # the check waits for the jump instead of reading the position once;
    # a page that never jumps still fails
    |> assert_script(
      "() => document.querySelector('#commentFilter').getBoundingClientRect().top >= 0",
      &assert(&1 == true)
    )
  end

  test "an admin ticks some, then clears a whole wave into the trash", %{conn: conn} do
    article = published_post()

    Texttile.CommentsFixtures.wave!(article, 30)

    conn
    |> sign_in()
    |> open("/admin/comments?status=waiting")
    |> assert(contain_text(by_css("#commentTools"), "Select all"))
    |> assert(contain_text(by_css("#bulk-delete"), "Delete all 30"))
    |> click(by_css("#selectAll"))
    |> assert(contain_text(by_css("#commentTools"), "30 selected"))
    |> assert(count(by_css("#commentsList .cmt.on"), 25))
    # a box the browser ticked and the server took back shows as empty
    |> click(by_css("#commentsList .cmt:first-child input[type=checkbox]"))
    |> assert(contain_text(by_css("#commentTools"), "29 selected"))
    |> assert(count(by_css("#commentsList .cmt.on"), 24))
    |> refute(checked(by_css("#commentsList .cmt:first-child input")))
    |> refute(checked(by_css("#selectAll")))
    |> click(by_role(:button, name: "Delete 29"))
    |> assert(contain_text(by_css("#dialog"), "Delete 29 comments?"))
    |> click(by_css("#dialog-ok"))
    |> assert(contain_text(by_css("#commentFilter a[data-f='trash']"), "29"))
    |> assert(contain_text(by_css("#commentTools"), "Select all"))
    |> assert(contain_text(by_css("#bulk-delete"), "Delete all 1"))

    assert Texttile.Comments.status_counts()["trash"] == 29
  end

  test "an admin comments under their own name, and the list counts it", %{conn: conn, kb: kb} do
    {:ok, user} = Texttile.Accounts.update_display_name(kb, "Katharina")
    article = published_post(title: "Harbor mornings", body: "Fog over the pier.")

    session = conn |> sign_in() |> open_page(Articles.public_path(article))

    # The account answers who is writing: the form asks for the words.
    session
    |> assert(contain_text(by_css("#comment-as"), "Katharina"))
    |> refute_has(by_css("#comment-name"))
    |> assert(contain_text(by_css("#comments"), "You are signed in"))
    |> fill(by_label("Comment", exact: true), "Writing under my own name.")
    |> click(by_role(:button, name: "Post comment"))
    # No link to follow: it stands under the text at once.
    |> assert(contain_text(by_css("#comment-count"), "1 comment"))
    |> assert(contain_text(by_css("#comments"), "Writing under my own name."))
    |> refute_has(by_css("#comments") |> filter(has_text: "waiting for your confirmation"))

    # And the count travels to the reader's list.
    session
    |> open_page("/blog")
    |> assert(contain_text(by_css("#texts"), "1 comment"))

    assert [comment] = Texttile.Comments.for_article(article.id)
    assert comment.user_id == user.id
  end

  # The box under the form. The browser keeps the three fields, and the
  # next entry the reader opens starts filled in.
  test "the box fills the form in on the next entry", %{conn: conn} do
    one = published_post(title: "Harbor mornings", slug: "harbor-mornings")
    two = published_post(title: "Fog again", slug: "fog-again")

    session =
      conn
      |> open_page(Articles.public_path(one))
      |> fill(by_label("Name"), "Grandma Christel")
      |> fill(by_css("#comment-email"), "christel@example.org")
      |> fill(by_label("Comment", exact: true), "More of the dog, please.")
      |> check(by_label("Remember me on this device"))
      |> age_form({:comment, one.id})
      |> click(by_role(:button, name: "Post comment"))
      |> assert(contain_text(by_css("#comment-note"), "Sent."))

    session
    |> open_page(Articles.public_path(two))
    |> assert_has(by_css("#comment-name[value='Grandma Christel']"))
    |> assert_has(by_css("#comment-email[value='christel@example.org']"))
  end
end
