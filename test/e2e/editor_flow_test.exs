defmodule TexttileWeb.E2E.EditorFlowTest do
  # Not async: SQLite serializes writers, concurrent sandbox owners flake.
  use PhoenixTest.Playwright.Case, async: false

  import Texttile.AccountsFixtures

  alias Texttile.Articles

  @moduletag :e2e

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
      |> visit("/texts/#{article.id}")
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
