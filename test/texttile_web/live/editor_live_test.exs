defmodule TexttileWeb.EditorLiveTest do
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Texttile.Articles
  alias Texttile.Articles.Lock

  setup :register_and_log_in_user

  # Lock processes outlive the SQL sandbox, so each test starts clean.
  setup do
    Lock.supervisor()
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(Lock.supervisor(), pid)
    end)

    :ok
  end

  defp draft(user, attrs \\ %{title: "Doors", body: "Wooden ones."}) do
    {:ok, article} = Articles.create_draft(user)
    {:ok, article} = Articles.update_text(article, attrs)
    article
  end

  describe "the editor" do
    test "shows the text and the crumb", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, view, html} = live(conn, ~p"/texts/#{article}")

      assert has_element?(view, "#crumb", "Doors")
      assert has_element?(view, "#edTitle[value='Doors']")
      assert html =~ "Wooden ones."
      assert has_element?(view, "#stamp", "draft")
    end

    test "autosaves the title", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      view |> element("#text-form") |> render_change(%{title: "Fourteen doors"})
      assert Articles.get_article!(article.id).title == "Fourteen doors"
      assert has_element?(view, "#crumb", "Fourteen doors")
    end

    test "autosaves the body from the editor hook", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      render_hook(view, "body_changed", %{"text" => "New words."})
      assert Articles.get_article!(article.id).body == "New words."
    end
  end

  describe "publish" do
    test "one click publishes a draft", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      view |> element("#stateBtn .main", "Publish") |> render_click()

      article = Articles.get_article!(article.id)
      assert article.status == "published"
      assert article.slug == "doors"
      assert has_element?(view, "#stamp", "published")
      assert has_element?(view, "#stateBtn .main", "Published")
    end

    test "a future date makes the click a scheduling", %{conn: conn, user: user} do
      article = draft(user)
      future = Date.utc_today() |> Date.add(7) |> Date.to_iso8601()
      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      view
      |> element("#artSettings")
      |> render_change(%{_target: ["publish_date"], publish_date: future})

      view |> element("#stateBtn .main", "Publish") |> render_click()

      assert Articles.get_article!(article.id).status == "scheduled"
      assert has_element?(view, "#stateBtn .main", "Scheduled")

      # the chevron menu of a scheduled text: publish now and unschedule
      view |> element("#stateBtn [aria-haspopup]") |> render_click()
      assert has_element?(view, "#stateMenu", "Publish now")
      assert has_element?(view, "#stateMenu", "Unschedule")
    end

    test "publish now forces a scheduled text live", %{conn: conn, user: user} do
      article = draft(user)

      {:ok, article} =
        Articles.set_publish_date(article, user, Date.add(Date.utc_today(), 7))

      {:ok, article} = Articles.publish(article, user)
      assert article.status == "scheduled"

      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")
      view |> element("#stateBtn [aria-haspopup]") |> render_click()
      view |> element("#stateMenu button", "Publish now") |> render_click()

      assert Articles.get_article!(article.id).status == "published"
    end

    test "unpublish from the chevron menu", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, article} = Articles.publish(article, user)

      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")
      view |> element("#stateBtn [aria-haspopup]") |> render_click()
      view |> element("#stateMenu button", "Unpublish") |> render_click()

      assert Articles.get_article!(article.id).status == "draft"
      assert has_element?(view, "#stateBtn .main", "Publish")
    end
  end

  describe "article settings" do
    test "tags and slug save on change", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      view
      |> element("#artSettings")
      |> render_change(%{_target: ["tags"], tags: "travel, doors"})

      assert Articles.get_article!(article.id).tags == "travel, doors"

      view
      |> element("#artSettings")
      |> render_change(%{_target: ["slug"], slug: "doors-of-vilnius"})

      assert Articles.get_article!(article.id).slug == "doors-of-vilnius"
    end

    test "a page hides the tags field and never emails", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      assert has_element?(view, "#fieldTags")
      view |> element("#artSettings") |> render_change(%{_target: ["type"], type: "page"})
      refute has_element?(view, "#fieldTags")
      assert has_element?(view, "#notifyOpt", "Pages never email anyone")
    end

    test "clearing the date of a published text unpublishes it", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, _} = Articles.publish(article, user)

      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      view
      |> element("#artSettings")
      |> render_change(%{_target: ["publish_date"], publish_date: ""})

      assert Articles.get_article!(article.id).status == "draft"
    end
  end

  describe "versions" do
    test "save version, then the tab shows it with a diff", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      view |> element("#btnSave") |> render_click()
      render_hook(view, "body_changed", %{"text" => "Iron ones."})
      view |> element("#btnSave") |> render_click()

      view |> element(".tab", "Versions") |> render_click()
      assert has_element?(view, "#versionsList .dif-add", "Iron")
      assert has_element?(view, "#versionsList .dif-del", "Wooden")
    end

    test "restore puts the old text back", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      view |> element("#btnSave") |> render_click()
      render_hook(view, "body_changed", %{"text" => "Iron ones."})

      view |> element(".tab", "Versions") |> render_click()
      view |> element("#versionsList button", "Restore this version") |> render_click()

      assert Articles.get_article!(article.id).body == "Wooden ones."
    end
  end

  describe "images in the text" do
    test "the panel reads the body: done, running and failed", %{conn: conn, user: user} do
      body = """
      Prose.

      ![pier](/uploads/images/pier-abcd.jpg)

      ![Uploading gull.jpg…]()

      ![Upload failed: fog.png]()
      """

      article = draft(user, %{title: "Doors", body: body})
      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      assert has_element?(view, "#inlineCount", "1 image · 1 on the way · 1 failed")
      assert has_element?(view, "#inlineImgs", "pier-abcd.jpg")
      assert has_element?(view, "#inlineImgs button[data-img-action=cancel]")
      assert has_element?(view, "#inlineImgs button[data-img-action=retry]")
    end

    test "upload events reach the log and the progress display", %{conn: conn, user: user} do
      article = draft(user, %{title: "Doors", body: "![Uploading gull.jpg…]()"})
      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      render_hook(view, "images_inserted", %{"files" => ["gull.jpg"]})
      render_hook(view, "upload_progress", %{"file" => "gull.jpg", "pct" => 40})
      assert has_element?(view, "#inlineImgs", "uploading 40%")

      render_hook(view, "image_uploaded", %{"file" => "gull.jpg"})
      view |> element(".tab", "Log") |> render_click()
      assert has_element?(view, "#logList", "gull.jpg is in the text")
      assert has_element?(view, "#logList", "put gull.jpg into the text")
    end
  end

  describe "the gallery" do
    defp gallery_image(article, name, taken) do
      path = Path.join(System.tmp_dir!(), "tile-#{System.unique_integer([:positive])}.jpg")
      {:ok, black} = Vix.Vips.Operation.black(20, 10)

      {:ok, with_date} =
        Vix.Vips.Image.mutate(black, fn mut ->
          :ok = Vix.Vips.MutableImage.set(mut, "exif-ifd2-DateTimeOriginal", :gchararray, taken)
        end)

      :ok = Vix.Vips.Image.write_to_file(with_date, path)
      {:ok, image} = Texttile.Gallery.add_image(article, path, name)
      image
    end

    defp tile_order(html) do
      ~r/data-id="(\d+)"/ |> Regex.scan(html) |> Enum.map(fn [_, id] -> String.to_integer(id) end)
    end

    test "shows the tiles in gallery order, with the count", %{conn: conn, user: user} do
      article = draft(user)
      b = gallery_image(article, "b.jpg", "2024:05:02 09:00:00")
      a = gallery_image(article, "a.jpg", "2024:05:01 09:00:00")

      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      assert has_element?(view, "#tileCount", "2 images")
      assert has_element?(view, "#tileGrid [data-id='#{a.id}']")
      assert has_element?(view, "#tile-#{a.id} button.tile-del")
      assert tile_order(render(view)) == [a.id, b.id]
    end

    test "an image added elsewhere appears without a reload", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      assert has_element?(view, "#tileCount", "0 images")

      image = gallery_image(article, "new.jpg", "2024:05:01 09:00:00")

      assert has_element?(view, "#tileGrid [data-id='#{image.id}']")
      assert has_element?(view, "#tileCount", "1 image")
    end

    test "a drop writes a new date and every editor sees the order", %{conn: conn, user: user} do
      article = draft(user)
      a = gallery_image(article, "a.jpg", "2024:05:01 10:00:00")
      b = gallery_image(article, "b.jpg", "2024:05:01 12:00:00")
      c = gallery_image(article, "c.jpg", "2024:05:01 14:00:00")

      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")
      {:ok, other, _html} = live(conn, ~p"/texts/#{article}")

      ids = Enum.map([a.id, c.id, b.id], &to_string/1)
      render_hook(view, "gallery_reorder", %{"id" => to_string(c.id), "ids" => ids})

      assert Enum.map(Texttile.Gallery.list(article.id), & &1.id) == [a.id, c.id, b.id]
      assert tile_order(render(other)) == [a.id, c.id, b.id]
    end

    test "a stale order is refused and the truth re-rendered", %{conn: conn, user: user} do
      article = draft(user)
      a = gallery_image(article, "a.jpg", "2024:05:01 10:00:00")
      b = gallery_image(article, "b.jpg", "2024:05:01 12:00:00")

      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      render_hook(view, "gallery_reorder", %{"id" => to_string(a.id), "ids" => [to_string(a.id)]})

      assert Enum.map(Texttile.Gallery.list(article.id), & &1.id) == [a.id, b.id]
      assert tile_order(render(view)) == [a.id, b.id]
    end

    test "the lightbox date field resorts the gallery", %{conn: conn, user: user} do
      article = draft(user)
      a = gallery_image(article, "a.jpg", "2024:05:01 10:00:00")
      b = gallery_image(article, "b.jpg", "2024:05:01 12:00:00")

      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      render_hook(view, "gallery_set_date", %{
        "id" => to_string(a.id),
        "date" => "2024-05-01T13:00"
      })

      assert tile_order(render(view)) == [b.id, a.id]
    end

    test "delete takes the tile away at once, undo brings it back", %{conn: conn, user: user} do
      article = draft(user)
      a = gallery_image(article, "a.jpg", "2024:05:01 10:00:00")
      b = gallery_image(article, "b.jpg", "2024:05:01 12:00:00")

      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      render_hook(view, "gallery_delete", %{"id" => to_string(a.id)})
      assert tile_order(render(view)) == [b.id]

      render_hook(view, "gallery_undo", %{"id" => to_string(a.id)})
      assert tile_order(render(view)) == [a.id, b.id]
    end

    test "the gallery stays open without the lock", %{conn: conn, user: user} do
      article = draft(user)
      a = gallery_image(article, "a.jpg", "2024:05:01 10:00:00")
      b = gallery_image(article, "b.jpg", "2024:05:01 12:00:00")

      # The first view holds the lock; the reader still sorts tiles.
      {:ok, _writer, _html} = live(conn, ~p"/texts/#{article}")

      other = Texttile.AccountsFixtures.user_fixture()
      reader_conn = log_in_user(build_conn(), other)
      {:ok, reader, _html} = live(reader_conn, ~p"/texts/#{article}")

      ids = Enum.map([b.id, a.id], &to_string/1)
      render_hook(reader, "gallery_reorder", %{"id" => to_string(b.id), "ids" => ids})

      assert Enum.map(Texttile.Gallery.list(article.id), & &1.id) == [b.id, a.id]
    end

    test "the preview picker chooses, flags the tile, and lets go again", %{
      conn: conn,
      user: user
    } do
      article = draft(user)
      a = gallery_image(article, "a.jpg", "2024:05:01 10:00:00")
      b = gallery_image(article, "b.jpg", "2024:05:01 12:00:00")

      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")
      {:ok, other, _html} = live(conn, ~p"/texts/#{article}")

      # without a choice the first image wears the flag
      assert has_element?(view, "#tile-#{a.id} .cov")
      refute has_element?(view, "#tile-#{b.id} .cov")

      view |> element("#coverRow button[phx-value-path='#{b.path}']") |> render_click()

      assert Articles.get_article!(article.id).preview_path == b.path
      assert has_element?(view, "#tile-#{b.id} .cov")
      assert has_element?(view, "#coverRow button.on[phx-value-path='#{b.path}']")
      assert has_element?(other, "#tile-#{b.id} .cov")

      # the second click lets the first image speak again
      view |> element("#coverRow button[phx-value-path='#{b.path}']") |> render_click()

      assert Articles.get_article!(article.id).preview_path == nil
      assert has_element?(view, "#tile-#{a.id} .cov")
    end

    test "a forged preview path changes nothing", %{conn: conn, user: user} do
      article = draft(user)
      _a = gallery_image(article, "a.jpg", "2024:05:01 10:00:00")

      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      render_click(view, "set_preview", %{"path" => "images/forged-00000000.jpg"})

      assert Articles.get_article!(article.id).preview_path == nil
    end

    test "another admin's sort flashes the moved tile with their name", %{
      conn: conn,
      user: user
    } do
      article = draft(user)
      a = gallery_image(article, "a.jpg", "2024:05:01 10:00:00")
      b = gallery_image(article, "b.jpg", "2024:05:01 12:00:00")

      {:ok, watcher, _html} = live(conn, ~p"/texts/#{article}")

      mover_user = Texttile.AccountsFixtures.user_fixture()
      mover_conn = log_in_user(build_conn(), mover_user)
      {:ok, mover, _html} = live(mover_conn, ~p"/texts/#{article}")

      ids = Enum.map([b.id, a.id], &to_string/1)
      render_hook(mover, "gallery_reorder", %{"id" => to_string(b.id), "ids" => ids})

      b_id = b.id
      assert_push_event(watcher, "gallery_moved", %{id: ^b_id, note: note})
      assert note =~ "moved b.jpg"
    end

    test "gallery doings land in the log", %{conn: conn, user: user} do
      article = draft(user)
      a = gallery_image(article, "a.jpg", "2024:05:01 10:00:00")

      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      render_hook(view, "gallery_delete", %{"id" => to_string(a.id)})
      render_hook(view, "gallery_undo", %{"id" => to_string(a.id)})

      view |> element(".tab", "Log") |> render_click()
      assert has_element?(view, "#logList", "took a.jpg out of the gallery")
      assert has_element?(view, "#logList", "put a.jpg back")
    end
  end

  describe "log" do
    test "records what happened, newest first", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, _} = Articles.publish(article, user)

      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")
      view |> element(".tab", "Log") |> render_click()

      assert has_element?(view, "#logList .log-row", "published the text")
      assert has_element?(view, "#logList .log-row", "started the text")
    end
  end

  describe "delete" do
    test "asks first, then deletes and returns to the grid", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")

      view |> element("#stateBtn [aria-haspopup]") |> render_click()
      view |> element("#stateMenu button", "Delete this text") |> render_click()
      assert has_element?(view, "#dialog", "Delete")

      view |> element("#dialog button", "Delete the text") |> render_click()
      assert_redirect(view, "/")
      assert Articles.list_articles() == []
    end
  end

  describe "publishing while the other admin writes" do
    test "asks first, then publishes on confirm", %{conn: conn, user: user} do
      article = draft(user)
      other = Texttile.AccountsFixtures.user_fixture()
      conn2 = Phoenix.ConnTest.build_conn() |> log_in_user(other)

      # the first mount holds the lock; the second only reads along
      {:ok, _holder_view, _} = live(conn, ~p"/texts/#{article}")
      {:ok, reader_view, _} = live(conn2, ~p"/texts/#{article}")

      reader_view |> element("#stateBtn .main", "Publish") |> render_click()
      assert has_element?(reader_view, "#dialog", "is editing this text right now")
      assert Articles.get_article!(article.id).status == "draft"

      reader_view |> element("#dialog button", "Publish anyway") |> render_click()
      assert Articles.get_article!(article.id).status == "published"
    end
  end

  describe "restore without the lock" do
    test "is refused with a note instead of restoring", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, _} = Articles.save_version(article, user)
      {:ok, article} = Articles.update_text(article, %{body: "Newer words."})

      {:ok, _holder_view, _} = live(conn, ~p"/texts/#{article}")

      other = Texttile.AccountsFixtures.user_fixture()
      conn2 = Phoenix.ConnTest.build_conn() |> log_in_user(other)
      {:ok, reader_view, _} = live(conn2, ~p"/texts/#{article}")

      reader_view |> element(".tab", "Versions") |> render_click()
      reader_view |> element("#versionsList button", "Restore this version") |> render_click()

      assert Articles.get_article!(article.id).body == "Newer words."
      assert has_element?(reader_view, "#stateLine", "Take the text over first")
    end
  end

  describe "the soft lock" do
    defp second_session(article) do
      other = Texttile.AccountsFixtures.user_fixture()
      conn = Phoenix.ConnTest.build_conn() |> log_in_user(other)
      {:ok, view, _html} = live(conn, ~p"/texts/#{article}")
      {view, other}
    end

    defp wait_until(fun, timeout \\ 3000) do
      deadline = System.monotonic_time(:millisecond) + timeout

      Stream.repeatedly(fn ->
        if fun.() do
          true
        else
          if System.monotonic_time(:millisecond) > deadline, do: raise("condition never met")
          Process.sleep(50)
          false
        end
      end)
      |> Enum.find(& &1)
    end

    test "the second person gets the text read-only and sees who writes",
         %{conn: conn, user: user} do
      article = draft(user)
      {:ok, _first, _} = live(conn, ~p"/texts/#{article}")

      {second, _other} = second_session(article)

      assert has_element?(second, "#edTitle[readonly]")
      assert has_element?(second, "#jbar")
    end

    test "the reader sees the text live", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, first, _} = live(conn, ~p"/texts/#{article}")
      {second, _other} = second_session(article)

      # the body travels over PubSub; the panel under the text is a
      # reading of the body, so the reader's panel shows the new image
      # reference (the editor surface itself is client-side DOM the
      # test cannot see into)
      render_hook(first, "body_changed", %{
        "text" => "Fresh words.\n\n![pier](/uploads/images/pier-fresh.jpg)"
      })

      wait_until(fn -> has_element?(second, "#inlineImgs", "pier-fresh.jpg") end)
    end

    test "a transport close keeps the lock through the grace period", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, view, _} = live(conn, ~p"/texts/#{article}")
      view_pid = view.pid

      # a reload or a network drop stops the channel with
      # {:shutdown, :closed}; the lock must stay held (grace), not free
      Process.flag(:trap_exit, true)
      ref = Process.monitor(view_pid)
      GenServer.stop(view_pid, {:shutdown, :closed})
      assert_receive {:DOWN, ^ref, :process, ^view_pid, _}

      assert %{user_id: user_id} = Lock.state(article.id)
      assert user_id == user.id
    end

    test "a deliberate leave releases the lock at once", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, view, _} = live(conn, ~p"/texts/#{article}")
      view_pid = view.pid

      Process.flag(:trap_exit, true)
      ref = Process.monitor(view_pid)
      GenServer.stop(view_pid, {:shutdown, :left})
      assert_receive {:DOWN, ^ref, :process, ^view_pid, _}

      assert Lock.state(article.id) == :free
    end

    test "an idle release is not taken straight back by the idle tab",
         %{conn: conn, user: user} do
      article = draft(user)
      {:ok, view, _} = live(conn, ~p"/texts/#{article}")

      [{lock_pid, _}] = Registry.lookup(Lock.registry(), article.id)
      send(lock_pid, :idle_over)

      # the released tab hears the announcement and must not re-acquire
      wait_until(fn -> has_element?(view, "#edTitle[readonly]") end)
      assert Lock.state(article.id) == :free

      # clicking back into the text takes it again, without a dialog
      view |> element("#edTitle") |> render_click()
      refute has_element?(view, "#edTitle[readonly]")
      assert %{user_id: user_id} = Lock.state(article.id)
      assert user_id == user.id
    end

    test "the takeover moves the lock and turns the other side read-only",
         %{conn: conn, user: user} do
      article = draft(user)
      {:ok, first, _} = live(conn, ~p"/texts/#{article}")
      {second, _other} = second_session(article)

      # the read-only side clicks into the title and confirms the dialog
      second |> element("#edTitle") |> render_click()
      assert has_element?(second, "#dialog", "Take the text over")
      second |> element("#dialog button", "Take over the text") |> render_click()

      # the flush answers (or its fallback fires), then the lock moves
      wait_until(fn -> not has_element?(second, "#edTitle[readonly]") end)
      wait_until(fn -> has_element?(first, "#edTitle[readonly]") end)

      # the handover snapshot exists, so nothing of the old text is lost
      assert Articles.versions(article) != []
    end
  end
end
