defmodule TexttileWeb.NewsletterLiveTest do
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Texttile.Newsletter

  setup :register_and_log_in_user

  defp join!(email) do
    {:ok, subscriber} = Newsletter.join(email, confirm_url: &"http://test/#{&1}")
    subscriber
  end

  test "an empty list says who will show up here", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/newsletter")

    assert has_element?(view, "#crumb", "Newsletter")
    assert has_element?(view, "#subList", "Nobody is on the list yet")
    assert has_element?(view, "#newsletterRule")
  end

  test "the wordmark menu carries the entry with its key", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/newsletter")
    assert has_element?(view, ~s(#navMenu a[data-key="7"]), "Newsletter")
  end

  test "lists subscribers newest first and tells confirmed from waiting", %{conn: conn} do
    {:ok, confirmed} = Newsletter.add("one@example.org")
    waiting = join!("two@example.org")

    {:ok, view, _html} = live(conn, ~p"/admin/newsletter")

    assert has_element?(view, "#sub-#{confirmed.id}", "one@example.org")
    refute has_element?(view, "#sub-#{confirmed.id}", "waits")
    assert has_element?(view, "#sub-#{waiting.id}", "two@example.org")
    assert has_element?(view, "#sub-#{waiting.id}", "waits")
    assert has_element?(view, "#newsletterSub", "1 address gets the texts")
  end

  test "adding an address puts it on the list confirmed, live for the whole desk", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/newsletter")
    {:ok, other, _html} = live(conn, ~p"/admin/newsletter")

    view
    |> form("#subAdd", %{"email" => "new@example.org"})
    |> render_submit()

    assert has_element?(view, "#subList", "new@example.org")
    assert has_element?(other, "#subList", "new@example.org")

    [subscriber] = Newsletter.list()
    assert Newsletter.Subscriber.confirmed?(subscriber)
  end

  test "an address that is not one gets a word and stays off the list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/newsletter")

    view
    |> form("#subAdd", %{"email" => "nope"})
    |> render_submit()

    assert has_element?(view, "#subAddError")
    assert Newsletter.list() == []
  end

  test "remove takes the address off the list, and a double remove is no crash", %{conn: conn} do
    {:ok, subscriber} = Newsletter.add("one@example.org")

    {:ok, one, _html} = live(conn, ~p"/admin/newsletter")
    {:ok, two, _html} = live(conn, ~p"/admin/newsletter")

    one |> element("#sub-#{subscriber.id} button", "Remove") |> render_click()
    render_click(two, "remove", %{"id" => subscriber.id})

    refute has_element?(one, "#sub-#{subscriber.id}")
    refute has_element?(two, "#sub-#{subscriber.id}")
    assert Newsletter.list() == []
  end

  test "a reader joining shows up without a reload", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/newsletter")

    subscriber = join!("fresh@example.org")
    assert has_element?(view, "#sub-#{subscriber.id}", "fresh@example.org")
  end
end
