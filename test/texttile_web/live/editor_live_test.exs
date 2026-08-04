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

  describe "the soft lock" do
    test "the second person gets the text read-only", %{conn: conn, user: user} do
      article = draft(user)
      {:ok, _first, _} = live(conn, ~p"/texts/#{article}")

      other = Texttile.AccountsFixtures.user_fixture()
      conn2 = Phoenix.ConnTest.build_conn() |> log_in_user(other)
      {:ok, second, _} = live(conn2, ~p"/texts/#{article}")

      assert has_element?(second, "#edTitle[readonly]")
      assert has_element?(second, "#jbar")
    end
  end
end
