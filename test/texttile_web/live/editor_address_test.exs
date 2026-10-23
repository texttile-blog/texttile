defmodule TexttileWeb.EditorAddressTest do
  use TexttileWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Texttile.Articles

  setup :register_and_log_in_user

  for status <- ~w(published scheduled),
      {name, attrs} <- [
        {"post without a slug", %{type: "post", slug: nil, publish_date: ~D[2026-08-08]}},
        {"page without a slug", %{type: "page", slug: nil, publish_date: ~D[2026-08-08]}},
        {"post without a date", %{type: "post", slug: "doors", publish_date: nil}}
      ] do
    test "opens and offers deletion for a #{status} #{name}", %{conn: conn, user: user} do
      {:ok, article} = Articles.create_draft(user)

      # Existing entries can carry a publication state without a public address.
      article =
        article
        |> Ecto.Changeset.change(Map.put(unquote(Macro.escape(attrs)), :status, unquote(status)))
        |> Texttile.Repo.update!()

      assert Articles.public_path(article) == nil
      {:ok, view, _html} = live(conn, ~p"/admin/texts/#{article}")
      assert has_element?(view, "#edSlug")
      refute has_element?(view, "#slugHint", "is live")

      view |> element("#stateChev") |> render_click()
      view |> element("#stateMenu button", "Delete") |> render_click()
      assert has_element?(view, "#dialog-ok", "Delete the entry")
      refute has_element?(view, "#dialog", "gets a 404 page")
    end
  end

  test "clearing and restoring a live address keeps both editors usable", %{
    conn: conn,
    user: user
  } do
    {:ok, article} = Articles.create_draft(user)
    {:ok, article} = Articles.update_text(article, %{title: "Doors", body: "Wooden ones."})
    {:ok, article} = Articles.publish(article, user)
    {:ok, writer, _html} = live(conn, ~p"/admin/texts/#{article}")

    watcher_conn =
      build_conn()
      |> log_in_user(Texttile.AccountsFixtures.user_fixture())

    {:ok, watcher, _html} = live(watcher_conn, ~p"/admin/texts/#{article}")
    assert has_element?(writer, "#slugHint", "is live")

    writer |> element("#artSettings") |> render_change(%{_target: ["slug"], slug: ""})

    assert Articles.get_article!(article.id).slug == nil
    refute has_element?(writer, "#slugHint", "is live")
    refute has_element?(watcher, "#slugHint", "is live")
    {:ok, reloaded, _html} = live(conn, ~p"/admin/texts/#{article}")
    assert has_element?(reloaded, "#edSlug")

    writer
    |> element("#artSettings")
    |> render_change(%{_target: ["slug"], slug: "restored-doors"})

    assert Articles.get_article!(article.id).slug == "restored-doors"
    assert has_element?(writer, "#slugHint", "restored-doors is live")
    assert has_element?(watcher, "#slugHint", "restored-doors is live")
  end
end
