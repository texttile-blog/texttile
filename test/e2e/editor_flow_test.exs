defmodule TexttileWeb.E2E.EditorFlowTest do
  use TexttileWeb.E2E

  alias Texttile.Articles

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
        eventually(fn ->
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

      eventually(fn ->
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

    # The chevron used to be a toggle, and a click on an open menu is
    # also a click away from it. The menu answered both, closed on the
    # one and opened again on the other, so it never went down.
    test "a second click on the chevron closes the menu again", %{conn: conn} do
      conn
      |> sign_in()
      |> click_button("New entry")
      |> click("#stateChev")
      |> assert_has("#stateMenu", text: "Save version")
      |> click("#stateChev")
      |> refute_has("#stateMenu")
      |> click("#stateChev")
      |> assert_has("#stateMenu", text: "Save version")
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
      other = Articles.create_draft(user_fixture(%{display_name: "julia"}))
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

    # A comma used to be the only way to close a word, which is a thing
    # somebody has to tell you. Enter is the key a field is finished
    # with everywhere else.
    test "Enter finishes the word the same way a comma does", %{conn: conn} do
      conn
      |> sign_in()
      |> click_button("New entry")
      |> fill_in("Title", with: "Tagged with Enter")
      |> type("#edTags", "harbor")
      |> press("#edTags", "Enter")
      |> assert_has("#tagchip-harbor.on")
      # and the field is ready for the next word
      |> evaluate(
        "() => document.getElementById('edTags').value",
        [is_function: true],
        fn value ->
          assert value == "harbor, "
        end
      )
    end

    # A word the blog does not carry yet had no row of its own, so the
    # menu answered every word but the one being written.
    test "a word the blog does not know stands in the menu as the only row",
         %{conn: conn} do
      {:ok, other} = Articles.create_draft(user_fixture(%{display_name: "julia"}))
      {:ok, _} = Articles.update_settings(other, %{tags: "harbor"})

      session =
        conn
        |> sign_in()
        |> click_button("New entry")
        |> fill_in("Title", with: "A tag of its own")
        |> type("#edTags", "estuary")
        |> assert_has(~s(#tagMenu li.fresh[data-tag="estuary"]))
        |> assert_has("#tagMenu li", count: 1)

      # and the marked row is the one Enter takes
      session
      |> press("#edTags", "Enter")
      |> assert_has("#tagchip-estuary.on")
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
        # the loud state of the line is the save itself answering. The
        # quiet stamp under it only returns when the flash has faded,
        # and waiting for that costs the suite three seconds.
        |> assert_has("#state.fresh")
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

  describe "the author" do
    # A closed select shows its options to nobody, Playwright included,
    # so the name the field stands on is read from the field itself.
    @author_field """
    () => document.querySelector("#edAuthor").selectedOptions[0].textContent.trim()
    """

    test "the field hands the entry to another admin, and the page says so",
         %{conn: conn, kb: kb} do
      anna = user_fixture(%{display_name: "Anna Berger"})
      article = published_post(user: kb, title: "Harbor mornings")

      conn =
        conn
        |> sign_in()
        |> open_editor(article.id)
        |> evaluate(@author_field, [is_function: true], &assert(&1 == "kb"))
        |> select("Author", option: "Anna Berger")
        |> assert_has("#state", text: "Last saved")

      moved =
        eventually(fn ->
          match?(%{user_id: id} when id == anna.id, Articles.get_article!(article.id))
        end)

      assert moved

      # the move is the entry's own story, and the reader gets the name
      conn
      |> click_button(".tab", "Log")
      |> assert_has("#logList", text: "named Anna Berger as the author")
      |> open_page(Articles.public_path(article))
      |> assert_has("#by", text: "Anna Berger")
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
    # The address is one field now (round 19): `.addr` carries the
    # ground, the rule and the room inside, and the slug inside it is a
    # bare input. So the lines to pass on are held against the field for
    # the ground and the room, and against the slug for the size of the
    # words, which is what both of them are: an address you read.
    @share_ground """
    () => {
      const one = getComputedStyle(document.querySelector("#shareLines"))
      const field = getComputedStyle(document.querySelector(".addr"))
      const slug = getComputedStyle(document.querySelector("#edSlug"))
      return [one.backgroundColor, field.backgroundColor,
              one.fontSize, slug.fontSize, one.padding, field.padding]
    }
    """

    # The word for the state used to blink, because the rule that makes
    # a presence dot pulse was written for the bare class the state word
    # also wears. A word that reads "Published" and then fades out reads
    # as a warning, and it is a fact. The dot still pulses: the probe
    # says so, so a rule that got deleted instead of narrowed is seen.
    @state_motion """
    () => {
      const word = getComputedStyle(document.querySelector("#stateWord")).animationName
      const probe = document.createElement("span")
      probe.className = "dot live"
      document.body.appendChild(probe)
      const dot = getComputedStyle(probe).animationName
      probe.remove()
      return [word, dot]
    }
    """

    test "the word for a live entry stands still, the presence dot pulses", %{conn: conn} do
      article = Texttile.ArticlesFixtures.published_post(title: "Out there")

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> assert_has("#stateWord", text: "Published")
      |> evaluate(@state_motion, [is_function: true], fn [word, dot] ->
        assert word == "none"
        assert dot == "pulse"
      end)
    end

    # The files in the text are a table, so the eye reads down a column
    # instead of hunting along a row. They were a flex row whose cells
    # each began where the cell before it ended, so no two rows lined
    # up and a long name pushed everything after it.
    @inline_columns """
    () => {
      const left = (selector) =>
        [...document.querySelectorAll(selector)].map(el => Math.round(el.getBoundingClientRect().left))
      return [left("#inlineImgs .nm"), left("#inlineImgs .raw")]
    }
    """

    test "the files in the text line up in columns", %{conn: conn} do
      %{id: id} =
        Texttile.ArticlesFixtures.published_post(
          title: "Two files",
          body: """
          One ![a](/uploads/images/pier.jpg) here.

          Two ![b](/uploads/images/a-much-longer-name-than-the-other-one.jpg) there.
          """
        )

      conn
      |> sign_in()
      |> open_editor(id)
      |> assert_has("#inlineCount", text: "2")
      |> evaluate(@inline_columns, [is_function: true], fn [names, raws] ->
        assert length(names) == 2
        assert length(raws) == 2
        assert Enum.uniq(names) == [hd(names)]
        assert Enum.uniq(raws) == [hd(raws)]
      end)
    end

    # An upload that stopped is a dead end without Retry and Remove,
    # and a running one without Cancel. On a phone the narrow grid used
    # to drop them into the 36px column of the thumbnail, where they
    # stood off the left edge of the screen.
    @stopped_actions """
    () => {
      const row = document.querySelector("#inlineImgs .inrow .act")
      const buttons = [...row.querySelectorAll("button")].map(b => b.getBoundingClientRect())
      return [row.getBoundingClientRect().width,
              Math.min(...buttons.map(b => b.left)),
              Math.max(...buttons.map(b => b.right)),
              window.innerWidth]
    }
    """

    @tag browser_context_opts: [viewport: %{width: 390, height: 844}]
    test "the way out of a stopped upload is on the screen of a phone", %{conn: conn} do
      %{id: id} =
        Texttile.ArticlesFixtures.published_post(
          title: "Stopped",
          body: "One ![Upload failed: pier.jpg]() here."
        )

      conn
      |> sign_in()
      |> open_editor(id)
      |> assert_has("#inlineImgs", text: "pier.jpg")
      |> evaluate(@stopped_actions, [is_function: true], fn [width, left, right, screen] ->
        assert width > 100
        assert left >= 0
        assert right <= screen
      end)
    end

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
end
