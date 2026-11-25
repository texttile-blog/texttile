defmodule TexttileWeb.E2E.EditorFlowTest do
  use TexttileWeb.E2E

  alias Texttile.Articles

  describe "writing" do
    test "a new text: title and body autosave, the live preview renders", %{conn: conn} do
      conn
      |> sign_in()
      |> click(by_role(:button, name: "New entry"))
      |> assert(contain_text(by_css("#crumb"), "Untitled"))
      |> fill(by_label("Title", exact: true), "Fourteen doors")
      |> assert(contain_text(by_css("#crumb"), "Fourteen doors"))
      |> press_sequentially(
        by_css(".ed-cm .cm-content"),
        "## The doors\n\nSome are **wooden**, some are not."
      )
      # the live preview: the heading line is styled, the caret's line
      # stays raw, and the finished bold line hides its asterisks
      |> assert(contain_text(by_css(".cm-mdh2"), "The doors"))

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
      |> assert_has(by_css("#edTitle[value='Fourteen doors']"))
      |> assert(contain_text(by_css(".ed-cm"), "The doors"))
    end

    test "the formatting bar writes markdown through the same commands", %{conn: conn} do
      conn =
        conn
        |> sign_in()
        |> click(by_role(:button, name: "New entry"))
        |> press_sequentially(by_css(".ed-cm .cm-content"), "strong words")

      # select the line, then bold it from the bar
      conn
      |> press(by_css(".ed-cm .cm-content"), "ControlOrMeta+a")
      |> click(by_css("[data-cmd=bold]"))

      eventually(fn ->
        match?([%{body: "**strong words**"}], Articles.list_articles())
      end)
    end
  end

  describe "publish" do
    test "an empty live address can be restored after reloading the editor", %{conn: conn, kb: kb} do
      article = draft!(kb, "Doors")
      {:ok, article} = Articles.publish(article, kb)

      conn =
        conn
        |> sign_in()
        |> open_editor(article.id)
        |> click(by_css("#edSlug"))
        |> press(by_css("#edSlug"), "ControlOrMeta+a")
        |> press(by_css("#edSlug"), "Backspace")
        |> click(by_css("#slugSet"))
        |> assert(contain_text(by_css("#dialog"), "no address of its own"))
        |> click(by_css("#dialog-ok"))

      eventually(fn -> Articles.get_article!(article.id).slug == nil end)

      conn
      |> open_editor(article.id)
      |> press_sequentially(by_css("#edSlug"), "restored-doors")
      |> click(by_css("#slugSet"))
      |> click(by_css("#dialog-ok"))
      |> assert_has(by_css(~s(#slugHint[data-live$="/restored-doors"])))

      assert Articles.get_article!(article.id).slug == "restored-doors"
    end

    test "one click publishes; the chevron menu unpublishes", %{conn: conn} do
      conn =
        conn
        |> sign_in()
        |> click(by_role(:button, name: "New entry"))
        |> fill(by_label("Title", exact: true), "Going live")
        |> click(by_css("#stateBtn .main") |> filter(has_text: "Publish"))
        |> assert(text(by_css("#stateWord"), "Live"))
        |> assert_has(by_css("#slugHint[data-live]"))

      assert [%{status: "published", slug: "going-live"}] = Articles.list_articles()

      conn
      |> click(by_css("#stateChev"))
      |> click(by_role(:button, name: "Unpublish"))
      |> assert(contain_text(by_css("#stateWord"), "Draft"))

      assert [%{status: "draft"}] = Articles.list_articles()
    end

    test "a live entry opens at its dated address through the bar", %{conn: conn} do
      today = Date.utc_today()

      conn =
        conn
        |> sign_in()
        |> click(by_role(:button, name: "New entry"))
        # a draft with no slug has no address of its own yet, and the
        # door is still there: it opens the same page by id, from the
        # one menu the bar carries
        |> click(by_css("#stateChev"))
        |> assert(contain_text(by_css("a#viewRow[href^='/preview/']"), "Open the entry"))
        |> click(by_css("#stateChev"))
        |> fill(by_label("Title", exact: true), "Going live")
        |> click(by_css("#stateBtn .main") |> filter(has_text: "Publish"))
        |> assert(text(by_css("#stateWord"), "Live"))

      address =
        "/#{today.year}/#{String.pad_leading("#{today.month}", 2, "0")}/" <>
          "#{String.pad_leading("#{today.day}", 2, "0")}/going-live"

      conn
      |> assert(contain_text(by_css("#stateBtn a#stateMain[href='#{address}']"), "View"))
      |> visit(address)
      |> assert(contain_text(by_css("h1"), "Going live"))

      # the bare slug is not an address of the text
      conn |> visit("/going-live") |> assert(contain_text(by_css("h1"), "Nothing here"))
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
      |> click(by_role(:button, name: "New entry"))
      |> assert_has(by_css(".mdbar"))
      |> click(by_css("#wmBtn"))
      |> assert(contain_text(by_css("#navMenu"), "View site"))
      |> assert_script(@stacking, &assert(&1 == "menu"))
    end

    # The chevron used to be a toggle, and a click on an open menu is
    # also a click away from it. The menu answered both, closed on the
    # one and opened again on the other, so it never went down.
    test "a second click on the chevron closes the menu again", %{conn: conn} do
      conn
      |> sign_in()
      |> click(by_role(:button, name: "New entry"))
      |> click(by_css("#stateChev"))
      |> assert(contain_text(by_css("#stateMenu"), "Save version"))
      |> click(by_css("#stateChev"))
      |> refute_has(by_css("#stateMenu"))
      |> click(by_css("#stateChev"))
      |> assert(contain_text(by_css("#stateMenu"), "Save version"))
    end

    test "the site opens beside the admin area, in its own tab", %{conn: conn} do
      conn
      |> sign_in()
      |> click(by_css("#wmBtn"))
      |> assert(
        contain_text(
          by_css(~s(#navMenu a[href="/"][target="_blank"][rel="noopener"])),
          "View site"
        )
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
      |> click(by_role(:button, name: "New entry"))
      |> fill(by_label("Title", exact: true), "Tagged by hand")
      |> click(by_css("#tagchip-sea"))
      |> assert_has(by_css("#tagchip-sea.on"))
      |> assert_has(by_css("#edTags[value='sea']"))
      |> click(by_css("#tagchip-fog"))
      |> assert_has(by_css("#edTags[value='sea, fog']"))
      |> click(by_css("#tagchip-sea"))
      |> assert_has(by_css("#edTags[value='fog']"))
      |> refute_has(by_css("#tagchip-sea.on"))
      |> assert_has(by_css("#tagchip-sea"))
    end

    test "a half-written word is no tag until a comma or the way out",
         %{conn: conn} do
      session =
        conn
        |> sign_in()
        |> click(by_role(:button, name: "New entry"))
        |> fill(by_label("Title", exact: true), "Half a tag")
        |> press_sequentially(by_css("#edTags"), "har")

      # "har" is three letters on the way to "harbor" and nothing else.
      # Nothing on the page says whether the field stayed quiet, so the
      # test waits out the pause a field of the old kind saved after,
      # and then reads what the blog carries.
      Process.sleep(600)

      session
      |> refute_has(by_css("#tagchip-har"))
      |> refute_has(by_css("#tagPick"))

      assert Enum.all?(Articles.list_articles(), &(&1.tags == ""))

      # the comma ends the word, and only then is it a tag
      session = press_sequentially(session, by_css("#edTags"), "bor,")

      assert_has(session, by_css("#tagchip-harbor.on"))

      # what stands in the field after the comma follows on the way out
      session = press_sequentially(session, by_css("#edTags"), " pier")
      Process.sleep(600)
      refute_has(session, by_css("#tagchip-pier"))

      session
      |> click(by_css("#edTitle"))
      |> assert_has(by_css("#tagchip-pier.on"))
    end

    # A comma used to be the only way to close a word, which is a thing
    # somebody has to tell you. Enter is the key a field is finished
    # with everywhere else.
    test "Enter finishes the word the same way a comma does", %{conn: conn} do
      conn
      |> sign_in()
      |> click(by_role(:button, name: "New entry"))
      |> fill(by_label("Title", exact: true), "Tagged with Enter")
      |> press_sequentially(by_css("#edTags"), "harbor")
      |> press(by_css("#edTags"), "Enter")
      |> assert_has(by_css("#tagchip-harbor.on"))
      # and the field is ready for the next word
      |> assert(value(by_css("#edTags"), "harbor, "))
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
        |> click(by_role(:button, name: "New entry"))
        |> fill(by_label("Title", exact: true), "A tag of its own")
        |> press_sequentially(by_css("#edTags"), "estuary")
        |> assert_has(by_css(~s(#tagMenu li.fresh[data-tag="estuary"])))
        |> assert(count(by_css("#tagMenu li"), 1))

      # and the marked row is the one Enter takes
      session
      |> press(by_css("#edTags"), "Enter")
      |> assert_has(by_css("#tagchip-estuary.on"))
    end

    test "a tag nobody else carries leaves the row when it leaves the field",
         %{conn: conn} do
      conn
      |> sign_in()
      |> click(by_role(:button, name: "New entry"))
      |> fill(by_label("Title", exact: true), "Only tag")
      |> press_sequentially(by_css("#edTags"), "lonely,")
      |> assert_has(by_css("#tagchip-lonely.on"))
      |> press(by_css("#edTags"), "ControlOrMeta+a")
      |> press(by_css("#edTags"), "Backspace")
      |> click(by_css("#edTitle"))
      |> refute_has(by_css("#tagchip-lonely"))
    end
  end

  describe "versions" do
    test "save, edit, save: the diff shows what changed, restore puts it back",
         %{conn: conn} do
      conn =
        conn
        |> sign_in()
        |> click(by_role(:button, name: "New entry"))
        |> fill(by_label("Title", exact: true), "Versioned")
        |> press_sequentially(by_css(".ed-cm .cm-content"), "First words.")
        # the toast is the save itself answering
        |> assert(contain_text(by_css("#toast"), "Saved"))
        |> click(by_css("#stateChev"))
        |> click(by_css("#saveVersionRow"))
        |> assert(contain_text(by_css("#stateLine"), "Version saved"))

      conn =
        conn
        |> press(by_css(".ed-cm .cm-content"), "ControlOrMeta+a")
        |> press_sequentially(by_css(".ed-cm .cm-content"), "Second words.")
        |> click(by_css("#stateChev"))
        |> click(by_css("#saveVersionRow"))
        |> click(by_css(".tab") |> filter(has_text: "Versions"))
        |> assert_has(by_css("#versionsList .dif-add") |> filter(has_text: "Second"))
        |> assert_has(by_css("#versionsList .dif-del") |> filter(has_text: "First"))

      # the older version's restore puts the first text back; the
      # pre-restore state is snapshotted first, so nothing is lost
      conn
      |> click(
        by_css("#versionsList > div:nth-of-type(2) button")
        |> filter(has_text: "Restore this version")
      )
      |> assert(contain_text(by_css("#toast"), "restored"))

      assert [article] = Articles.list_articles()
      assert article.body == "First words."
      assert Enum.any?(Articles.versions(article), &(&1.body == "Second words."))
    end
  end

  describe "the author" do
    # A closed select shows its options to nobody, Playwright included,
    # so the name the field stands on is read from its chosen option.

    test "the field hands the entry to another admin, and the page says so",
         %{conn: conn, kb: kb} do
      anna = user_fixture(%{display_name: "Anna Berger"})
      article = published_post(user: kb, title: "Harbor mornings")

      conn =
        conn
        |> sign_in()
        |> open_editor(article.id)
        |> assert(text(by_css("#edAuthor option:checked"), "kb"))
        |> select_option(by_label("Author"), %{label: "Anna Berger"})
        |> assert(contain_text(by_css("#state"), "Saved"))

      moved =
        eventually(fn ->
          match?(%{user_id: id} when id == anna.id, Articles.get_article!(article.id))
        end)

      assert moved

      # the move is the entry's own story, and the reader gets the name
      conn
      |> click(by_css(".tab") |> filter(has_text: "Log"))
      |> assert(contain_text(by_css("#logList"), "named Anna Berger as the author"))
      |> open_page(Articles.public_path(article))
      |> assert(contain_text(by_css("#by"), "Anna Berger"))
    end
  end

  describe "the log" do
    test "the Log tab tells the story of the text", %{conn: conn} do
      conn
      |> sign_in()
      |> click(by_role(:button, name: "New entry"))
      |> fill(by_label("Title", exact: true), "Logged")
      |> click(by_css("#stateBtn .main") |> filter(has_text: "Publish"))
      |> click(by_css(".tab") |> filter(has_text: "Log"))
      |> assert(contain_text(by_css("#logList"), "published the entry"))
      |> assert(contain_text(by_css("#logList"), "started the entry"))
    end
  end

  describe "the writing surface" do
    # The glyphs format the words under them, so they belong to the
    # words: the bar stands closer to the body than to the title.
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
      |> click(by_role(:button, name: "New entry"))
      |> assert_has(by_css(".mdbar"))
      |> assert_script(@bar_gaps, fn [over, under] ->
        assert under < over
      end)
    end

    # Until the editor's chunk arrives, the server's textarea is the
    # surface. It drew a hairline of its own beside the host's and
    # stood its words elsewhere, so every load flashed two lines and a
    # jump. This puts the server's markup back in place of the editor
    # and measures both: no more lines are drawn than the editor draws
    # (none around the body, the field's own box around About), and
    # the words stand where the editor's words stood.
    @seed_surface """
    async (host) => {
      const live = document.querySelector(host)
      const content = live.querySelector(".cm-content")
      const cs = getComputedStyle(content)
      const r = content.getBoundingClientRect()
      const editor = [r.left + parseFloat(cs.paddingLeft), r.top + parseFloat(cs.paddingTop)]

      const html = await (await fetch(location.href)).text()
      const seed = new DOMParser().parseFromString(html, "text/html").querySelector(host)
      live.replaceWith(document.importNode(seed, true))

      const el = document.querySelector(host)
      const drawn = [el, ...el.querySelectorAll("*")].filter(n => {
        const s = getComputedStyle(n)
        return s.boxShadow !== "none" || parseFloat(s.borderLeftWidth) > 0
      })
      const ta = el.querySelector("textarea")
      const ts = getComputedStyle(ta)
      const t = ta.getBoundingClientRect()
      const words = [
        t.left + parseFloat(ts.borderLeftWidth) + parseFloat(ts.paddingLeft),
        t.top + parseFloat(ts.borderTopWidth) + parseFloat(ts.paddingTop)
      ]
      return {lines: drawn.length, shift: words.map((v, i) => Math.abs(v - editor[i]))}
    }
    """

    for {surface, path, host, lines} <- [
          {"the body", :editor, "#edBodyHost", 0},
          {"About", "/admin/settings", "#setting-about_markdown", 1}
        ] do
      test "#{surface} draws no second line and no jump while the editor loads", %{
        conn: conn,
        kb: kb
      } do
        conn = sign_in(conn)

        conn =
          case unquote(path) do
            :editor -> open_editor(conn, draft!(kb).id)
            path -> open(conn, path)
          end

        # the script puts the server's markup in place, so it runs once
        result =
          conn
          |> assert_has(by_css("#{unquote(host)} .cm-content"))
          |> evaluate(@seed_surface, unquote(host))

        assert result["lines"] == unquote(lines)
        assert Enum.all?(result["shift"], &(&1 < 1))
      end
    end

    # The surface takes Tab as a character, so without a key that lets
    # go the body is a room with only a mouse for a door.
    test "Escape leaves the body", %{conn: conn} do
      conn
      |> sign_in()
      |> click(by_role(:button, name: "New entry"))
      |> press_sequentially(by_css(".ed-cm .cm-content"), "Words.")
      |> assert_has(by_css(".cm-editor.cm-focused"))
      |> press(by_css(".ed-cm .cm-content"), "Escape")
      |> refute_has(by_css(".cm-editor.cm-focused"))
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
      |> click(by_role(:button, name: "New entry"))
      # The picker is in the markup before the editor's chunk has
      # loaded, and a file picked before that is lost in silence. The
      # surface and the picker's listener come up in the same step.
      |> assert_has(by_css(".ed-cm .cm-content"))
      |> set_input_files(by_label("Put pictures and videos in the text"), huge)
      |> assert(contain_text(by_css("#toast"), "over the 10 MB roof"))
      |> refute_has(by_css(".cm-content") |> filter(has_text: "Uploading"))
    end

    # The line drops, both pictures fail, the line comes back: one
    # button sends both again instead of a Retry per picture.
    test "failed pictures in the text go again with one button", %{conn: conn} do
      # two different pictures: the entry refuses the same one twice
      picture = fn width ->
        path = Path.join(System.tmp_dir!(), "e2e-#{System.unique_integer([:positive])}.png")
        {:ok, black} = Vix.Vips.Operation.black(width, 20)
        :ok = Vix.Vips.Image.write_to_file(black, path)
        path
      end

      conn
      |> sign_in()
      |> click(by_role(:button, name: "New entry"))
      # the picker listens once the surface stands, see the roof test
      |> assert_has(by_css(".ed-cm .cm-content"))
      |> run_script("""
      () => {
        window.realSend = XMLHttpRequest.prototype.send
        XMLHttpRequest.prototype.send = function () {
          setTimeout(() => this.dispatchEvent(new Event("error")))
        }
        return true
      }
      """)
      |> set_input_files(by_label("Put pictures and videos in the text"), picture.(40))
      |> assert(contain_text(by_css("#inlineCount"), "1 failed"))
      |> refute_has(by_css("#inlineResume"))
      |> set_input_files(by_label("Put pictures and videos in the text"), picture.(41))
      |> assert(contain_text(by_css("#inlineCount"), "2 failed"))
      |> run_script("() => { XMLHttpRequest.prototype.send = window.realSend; return true }")
      |> assert(contain_text(by_css("#inlineResume"), "2 uploads did not arrive"))
      |> click(by_css("#inlineResume button") |> filter(has_text: "Resume all"))
      |> assert(contain_text(by_css("#inlineCount"), "2 files"))
      |> refute_has(by_css("#inlineCount") |> filter(has_text: "failed"))
      |> refute_has(by_css("#inlineResume"))
    end

    # The same two can also leave at once: their markers go out of the
    # text, and nothing is sent.
    test "failed pictures in the text leave with one button", %{conn: conn} do
      picture = fn width ->
        path = Path.join(System.tmp_dir!(), "e2e-#{System.unique_integer([:positive])}.png")
        {:ok, black} = Vix.Vips.Operation.black(width, 20)
        :ok = Vix.Vips.Image.write_to_file(black, path)
        path
      end

      conn
      |> sign_in()
      |> click(by_role(:button, name: "New entry"))
      |> assert_has(by_css(".ed-cm .cm-content"))
      |> run_script("""
      () => {
        XMLHttpRequest.prototype.send = function () {
          setTimeout(() => this.dispatchEvent(new Event("error")))
        }
        return true
      }
      """)
      |> set_input_files(by_label("Put pictures and videos in the text"), picture.(40))
      |> assert(contain_text(by_css("#inlineCount"), "1 failed"))
      |> set_input_files(by_label("Put pictures and videos in the text"), picture.(41))
      |> assert(contain_text(by_css("#inlineCount"), "2 failed"))
      |> click(by_css("#inlineResume button") |> filter(has_text: "Remove all"))
      |> refute_has(by_css("#inlineResume"))
      |> refute_has(by_css("#inlineImgs [data-img-action=retry]"))
      |> refute_has(by_css(".ed-cm .cm-content") |> filter(has_text: "Upload failed"))
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
    # also wears. A word that reads "Live" and then fades out reads
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
      |> assert(text(by_css("#stateWord"), "Live"))
      |> assert_script(@state_motion, fn [word, dot] ->
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
      |> assert(contain_text(by_css("#inlineCount"), "2"))
      |> assert_script(@inline_columns, fn [names, raws] ->
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

    @tag Playwright.Test.use(viewport: %{width: 390, height: 844})
    test "the way out of a stopped upload is on the screen of a phone", %{conn: conn} do
      %{id: id} =
        Texttile.ArticlesFixtures.published_post(
          title: "Stopped",
          body: "One ![Upload failed: pier.jpg]() here."
        )

      conn
      |> sign_in()
      |> open_editor(id)
      |> assert(contain_text(by_css("#inlineImgs"), "pier.jpg"))
      |> assert_script(@stopped_actions, fn [width, left, right, screen] ->
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
      |> assert_has(by_css("#shareLines"))
      |> assert_script(@share_ground, fn [bg, other_bg, fs, other_fs, p, other_p] ->
        assert bg == other_bg
        assert fs == other_fs
        assert p == other_p
      end)
    end
  end

  describe "the phone's row of places" do
    # the jump is the browser's own and may glide, so the check waits
    # for the page to arrive
    @scrolled """
    (where) => where === "top" ? window.scrollY === 0 : window.scrollY > 300
    """

    @tag Playwright.Test.use(viewport: %{width: 390, height: 844})
    test "Text takes the writer back up from the settings", %{conn: conn} do
      body = Enum.map_join(1..40, "\n\n", &"Paragraph #{&1} of a long walk.")
      %{id: id} = Texttile.ArticlesFixtures.published_post(title: "Long", body: body)

      conn
      |> sign_in()
      |> open_editor(id)
      |> click(by_css("#jumpSettings"))
      |> assert_script(@scrolled, "down", &assert(&1 == true))
      |> click(by_css("#ptabText"))
      |> assert_script(@scrolled, "top", &assert(&1 == true))
    end
  end
end
