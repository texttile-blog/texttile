defmodule TexttileWeb.E2E.EditorFlowTest do
  # Not async: SQLite serializes writers, concurrent sandbox owners flake.
  use PhoenixTest.Playwright.Case, async: false

  import Texttile.AccountsFixtures

  alias Texttile.Articles

  @moduletag :e2e

  setup {TexttileWeb.E2E, :close_browser_context_afterwards}

  setup do
    Texttile.DataCase.restore_admin_users_afterwards()

    Texttile.Articles.Lock.supervisor()
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(Texttile.Articles.Lock.supervisor(), pid)
    end)

    %{kb: user_fixture(%{username: "kb"})}
  end

  describe "writing" do
    test "a new text: title and body autosave, the live preview renders", %{conn: conn} do
      conn
      |> sign_in()
      |> click_button("New text")
      |> assert_has("#crumb", text: "Untitled")
      |> fill_in("Title", with: "Fourteen doors")
      |> assert_has("#crumb", text: "Fourteen doors")
      |> type(".ed-cm .cm-content", "## The doors\n\nSome are **wooden**, some are not.")
      # the live preview: the heading line is styled, the caret's line
      # stays raw, and the finished bold line hides its asterisks
      |> assert_has(".cm-mdh2", text: "The doors")

      article =
        wait_until(fn ->
          case Articles.list_articles() do
            [%{body: body} = article] when body != "" -> article
            _ -> nil
          end
        end)

      assert article.title == "Fourteen doors"
      assert article.body =~ "## The doors"
      assert article.body =~ "**wooden**"

      # everything is still there after a full reload
      conn
      |> visit("/admin/texts/#{article.id}")
      |> assert_has("#edTitle[value='Fourteen doors']")
      |> assert_has(".ed-cm", text: "The doors")
    end

    test "the formatting bar writes markdown through the same commands", %{conn: conn} do
      conn =
        conn
        |> sign_in()
        |> click_button("New text")
        |> type(".ed-cm .cm-content", "strong words")

      # select the line, then bold it from the bar
      conn
      |> press(".ed-cm .cm-content", "ControlOrMeta+a")
      |> click("[data-cmd=bold]")

      wait_until(fn ->
        match?([%{body: "**strong words**"}], Articles.list_articles())
      end)
    end
  end

  describe "publish" do
    test "one click publishes; the chevron menu unpublishes", %{conn: conn} do
      conn =
        conn
        |> sign_in()
        |> click_button("New text")
        |> fill_in("Title", with: "Going live")
        |> click_button("#stateBtn .main", "Publish")
        |> assert_has("#stamp", text: "published")
        |> assert_has("#slugHint", text: "is live")

      assert [%{status: "published", slug: "going-live"}] = Articles.list_articles()

      conn
      |> click_button("#stateChev", "Published")
      |> click_button("Unpublish")
      |> assert_has("#stamp", text: "draft")

      assert [%{status: "draft"}] = Articles.list_articles()
    end

    test "a future date turns the click into a scheduling", %{conn: conn} do
      future = Date.utc_today() |> Date.add(14) |> Date.to_iso8601()

      conn
      |> sign_in()
      |> click_button("New text")
      |> fill_in("Title", with: "Later")
      |> fill_in("Publish date", with: future)
      |> click_button("#stateBtn .main", "Publish")
      |> assert_has("#stamp", text: "scheduled")
      |> assert_has("#edDateHint", text: "The subscriber email goes out on #{future}")

      assert [%{status: "scheduled"}] = Articles.list_articles()
    end

    test "a live text opens at its dated address through the bar", %{conn: conn} do
      today = Date.utc_today()

      conn =
        conn
        |> sign_in()
        |> click_button("New text")
        |> fill_in("Title", with: "Going live")
        |> refute_has("#btnView")
        |> click_button("#stateBtn .main", "Publish")
        |> assert_has("#stamp", text: "published")

      address =
        "/#{today.year}/#{String.pad_leading("#{today.month}", 2, "0")}/" <>
          "#{String.pad_leading("#{today.day}", 2, "0")}/going-live"

      conn
      |> assert_has("#btnView[href='#{address}']")
      |> visit(address)
      |> assert_has("h1", text: "Going live")

      # the bare slug is not an address of the text
      conn |> visit("/going-live") |> assert_has("h1", text: "Nothing here")
    end
  end

  describe "the bar over the editor" do
    # The bar blurs what runs under it, and a blur makes an element its
    # own layer: the menu inside the bar can only rise as high as the
    # bar itself. While the bar stood level with the formatting bar,
    # the glyphs were painted over the open menu.
    @stacking """
    () => {
      const menu = document.querySelector("#navMenu")
      const bar = document.querySelector(".mdbar")
      const m = menu.getBoundingClientRect(), b = bar.getBoundingClientRect()
      const overlaps = m.right > b.left && m.left < b.right &&
                       m.bottom > b.top && m.top < b.bottom
      if (!overlaps) return "the two never meet"
      const top = document.elementFromPoint(Math.min(m.right, b.right) - 6,
                                            Math.max(m.top, b.top) + 12)
      return menu.contains(top) ? "menu" : "covered"
    }
    """

    test "the open menu stands over the formatting glyphs", %{conn: conn} do
      conn
      |> sign_in()
      |> click_button("New text")
      |> assert_has(".mdbar")
      |> click("#wmBtn")
      |> assert_has("#navMenu", text: "View site")
      |> evaluate(@stacking, [is_function: true], &assert(&1 == "menu"))
    end

    test "the site opens beside the admin area, in its own tab", %{conn: conn} do
      conn
      |> sign_in()
      |> click("#wmBtn")
      |> assert_has(~s(#navMenu a[href="/"][target="_blank"][rel="noopener"]),
        text: "View site"
      )
    end
  end

  describe "tags" do
    test "the suggestions add a tag and take it off again", %{conn: conn} do
      other = Articles.create_draft(user_fixture(%{username: "julia"}))
      {:ok, other} = other
      {:ok, _} = Articles.update_settings(other, %{tags: "sea, fog"})

      conn
      |> sign_in()
      |> click_button("New text")
      |> fill_in("Title", with: "Tagged by hand")
      |> click("#tagchip-sea")
      |> assert_has("#tagchip-sea.on")
      |> assert_has("#edTags[value='sea']")
      |> click("#tagchip-fog")
      |> assert_has("#edTags[value='sea, fog']")
      |> click("#tagchip-sea")
      |> assert_has("#edTags[value='fog']")
      |> refute_has("#tagchip-sea.on")
      |> assert_has("#tagchip-sea")
    end

    test "a half-written word is no tag until a comma or the way out",
         %{conn: conn} do
      session =
        conn
        |> sign_in()
        |> click_button("New text")
        |> fill_in("Title", with: "Half a tag")
        |> type("#edTags", "har")

      # "har" is three letters on the way to "harbor" and nothing else.
      # Nothing on the page says whether the field stayed quiet, so the
      # test waits out the pause a field of the old kind saved after,
      # and then reads what the blog carries.
      Process.sleep(600)

      session
      |> refute_has("#tagchip-har")
      |> refute_has("#tagPick")

      assert Enum.all?(Articles.list_articles(), &(&1.tags == ""))

      # the comma ends the word, and only then is it a tag
      session = type(session, "#edTags", "bor,")

      assert_has(session, "#tagchip-harbor.on")

      # what stands in the field after the comma follows on the way out
      session = type(session, "#edTags", " pier")
      Process.sleep(600)
      refute_has(session, "#tagchip-pier")

      session
      |> click("#edTitle")
      |> assert_has("#tagchip-pier.on")
    end

    test "a tag nobody else carries leaves the row when it leaves the field",
         %{conn: conn} do
      conn
      |> sign_in()
      |> click_button("New text")
      |> fill_in("Title", with: "Only tag")
      |> type("#edTags", "lonely,")
      |> assert_has("#tagchip-lonely.on")
      |> press("#edTags", "ControlOrMeta+a")
      |> press("#edTags", "Backspace")
      |> click("#edTitle")
      |> refute_has("#tagchip-lonely")
    end
  end

  describe "versions" do
    test "save, edit, save: the diff shows what changed, restore puts it back",
         %{conn: conn} do
      conn =
        conn
        |> sign_in()
        |> click_button("New text")
        |> fill_in("Title", with: "Versioned")
        |> type(".ed-cm .cm-content", "First words.")
        |> assert_has("#state", text: "Last saved · just now")
        |> click_button("Save version")
        |> assert_has("#state", text: "Version saved")

      conn =
        conn
        |> press(".ed-cm .cm-content", "ControlOrMeta+a")
        |> type(".ed-cm .cm-content", "Second words.")
        |> click_button("Save version")
        |> click_button(".tab", "Versions")
        |> assert_has("#versionsList .dif-add", text: "Second")
        |> assert_has("#versionsList .dif-del", text: "First")

      # the older version's restore puts the first text back; the
      # pre-restore state is snapshotted first, so nothing is lost
      conn
      |> click("#versionsList > div:nth-of-type(2) button", "Restore this version")
      |> assert_has("#state", text: "restored")

      assert [article] = Articles.list_articles()
      assert article.body == "First words."
      assert Enum.any?(Articles.versions(article), &(&1.body == "Second words."))
    end
  end

  describe "the log" do
    test "the Log tab tells the story of the text", %{conn: conn} do
      conn
      |> sign_in()
      |> click_button("New text")
      |> fill_in("Title", with: "Logged")
      |> click_button("#stateBtn .main", "Publish")
      |> click_button(".tab", "Log")
      |> assert_has("#logList", text: "published the text")
      |> assert_has("#logList", text: "started the text")
    end
  end

  # The editor debounces its autosave; database asserts wait for it.
  defp wait_until(fun, timeout \\ 3000) do
    do_wait(fun, System.monotonic_time(:millisecond) + timeout)
  end

  defp do_wait(fun, deadline) do
    case fun.() do
      value when value not in [nil, false] ->
        value

      _ ->
        if System.monotonic_time(:millisecond) > deadline, do: raise("condition never met")
        Process.sleep(50)
        do_wait(fun, deadline)
    end
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
