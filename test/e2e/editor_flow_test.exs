defmodule TexttileWeb.E2E.EditorFlowTest do
  # Not async: SQLite serializes writers, concurrent sandbox owners flake.
  use PhoenixTest.Playwright.Case, async: false

  import Texttile.AccountsFixtures
  import TexttileWeb.E2E, only: [sign_in: 1, open_editor: 2]

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
      |> click_button("New entry")
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
      |> open_editor(article.id)
      |> assert_has("#edTitle[value='Fourteen doors']")
      |> assert_has(".ed-cm", text: "The doors")
    end

    test "the formatting bar writes markdown through the same commands", %{conn: conn} do
      conn =
        conn
        |> sign_in()
        |> click_button("New entry")
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
        |> click_button("New entry")
        |> fill_in("Title", with: "Going live")
        |> click_button("#stateBtn .main", "Publish")
        |> assert_has("#stateWord", text: "Published")
        |> assert_has("#slugHint", text: "is live")

      assert [%{status: "published", slug: "going-live"}] = Articles.list_articles()

      conn
      |> click("#stateChev")
      |> click_button("Unpublish")
      |> assert_has("#stateWord", text: "Draft")

      assert [%{status: "draft"}] = Articles.list_articles()
    end

    test "a future date turns the click into a scheduling", %{conn: conn} do
      future = Date.utc_today() |> Date.add(14) |> Date.to_iso8601()

      conn
      |> sign_in()
      |> click_button("New entry")
      |> fill_in("Title", with: "Later")
      |> fill_in("Publish date", with: future)
      |> click_button("#stateBtn .main", "Publish")
      |> assert_has("#stateWord", text: "Scheduled")
      |> assert_has("#edDateHint", text: "It goes live on #{future}")
      # the mail has one owner on this pane, and it is not the date
      |> assert_has("#notifyOpt", text: "Goes out to the confirmed subscribers")

      assert [%{status: "scheduled"}] = Articles.list_articles()
    end

    test "a live entry opens at its dated address through the bar", %{conn: conn} do
      today = Date.utc_today()

      conn =
        conn
        |> sign_in()
        |> click_button("New entry")
        # a draft with no slug has no address of its own yet, and the
        # door is still there: it opens the same page by id, from the
        # one menu the bar carries
        |> click("#stateChev")
        |> assert_has("a#viewRow[href^='/preview/']", text: "Open the entry")
        |> click("#stateChev")
        |> fill_in("Title", with: "Going live")
        |> click_button("#stateBtn .main", "Publish")
        |> assert_has("#stateWord", text: "Published")

      address =
        "/#{today.year}/#{String.pad_leading("#{today.month}", 2, "0")}/" <>
          "#{String.pad_leading("#{today.day}", 2, "0")}/going-live"

      conn
      |> assert_has("#stateBtn a#stateMain[href='#{address}']", text: "View")
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
      |> click_button("New entry")
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
      |> click_button("New entry")
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
        |> click_button("New entry")
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
      |> click_button("New entry")
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
        |> click_button("New entry")
        |> fill_in("Title", with: "Versioned")
        |> type(".ed-cm .cm-content", "First words.")
        |> assert_has("#state", text: "Last saved · just now")
        |> click("#stateChev")
        |> click_button("#saveVersionRow", "Save version")
        |> assert_has("#stateLine", text: "Version saved")

      conn =
        conn
        |> press(".ed-cm .cm-content", "ControlOrMeta+a")
        |> type(".ed-cm .cm-content", "Second words.")
        |> click("#stateChev")
        |> click_button("#saveVersionRow", "Save version")
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
      |> click_button("New entry")
      |> fill_in("Title", with: "Logged")
      |> click_button("#stateBtn .main", "Publish")
      |> click_button(".tab", "Log")
      |> assert_has("#logList", text: "published the entry")
      |> assert_has("#logList", text: "started the entry")
    end
  end

  describe "the writing surface" do
    # The glyphs format the words under them, so they belong to the
    # words. They stood 18px under the title and 26px over the body,
    # which read as a bar attached to the title.
    @bar_gaps """
    () => {
      const bar = document.querySelector(".mdbar").getBoundingClientRect()
      const title = document.querySelector("#edTitle").getBoundingClientRect()
      const body = document.querySelector("#edBodyHost").getBoundingClientRect()
      return [bar.top - title.bottom, body.top - bar.bottom]
    }
    """

    test "the formatting bar belongs to the body, not to the title", %{conn: conn} do
      conn
      |> sign_in()
      |> click_button("New entry")
      |> assert_has(".mdbar")
      |> evaluate(@bar_gaps, [is_function: true], fn [over, under] ->
        assert under < over
      end)
    end

    # The surface takes Tab as a character, so without a key that lets
    # go the body is a room with only a mouse for a door.
    test "Escape leaves the body", %{conn: conn} do
      conn
      |> sign_in()
      |> click_button("New entry")
      |> type(".ed-cm .cm-content", "Words.")
      |> assert_has(".cm-editor.cm-focused")
      |> press(".ed-cm .cm-content", "Escape")
      |> refute_has(".cm-editor.cm-focused")
    end

    # The body had no roof of its own: an oversize paste put a token in
    # the words, uploaded for as long as it took, and ended at the
    # parser. Now it is turned away before anything is written.
    test "a file over the roof never reaches the words", %{conn: conn} do
      {:ok, _} = Texttile.Settings.put(:max_upload_mb, 10)

      huge = Path.join(System.tmp_dir!(), "huge-#{System.unique_integer([:positive])}.jpg")
      {:ok, file} = File.open(huge, [:write])
      :ok = :file.pwrite(file, 11 * 1024 * 1024, <<0>>)
      :ok = File.close(file)

      conn
      |> sign_in()
      |> click_button("New entry")
      |> assert_has(".mdbar")
      |> upload("Put pictures and videos in the text", huge)
      |> assert_has("#state", text: "over the 10 MB roof")
      |> refute_has(".cm-content", text: "Uploading")
    end

    # The lines to hand on are a field of the pane, in the same clothes
    # as every other field beside them. They were a bare paragraph.
    @share_ground """
    () => {
      const one = getComputedStyle(document.querySelector("#shareLines"))
      const other = getComputedStyle(document.querySelector("#edSlug"))
      return [one.backgroundColor, other.backgroundColor,
              one.fontSize, other.fontSize, one.padding, other.padding]
    }
    """

    test "the share lines wear the clothes of the pane", %{conn: conn} do
      article = Texttile.ArticlesFixtures.published_post(title: "Handed on")

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> assert_has("#shareLines")
      |> evaluate(@share_ground, [is_function: true], fn [bg, other_bg, fs, other_fs, p, other_p] ->
        assert bg == other_bg
        assert fs == other_fs
        assert p == other_p
      end)
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
end
