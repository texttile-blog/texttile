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
      refute has_element?(view, "#slugHint[data-live]")

      view |> element("#stateChev") |> render_click()
      view |> element("#stateMenu button", "Delete") |> render_click()
      assert has_element?(view, "#dialog-ok", "Delete the entry")
      refute has_element?(view, "#dialog", "gets a 404 page")
    end
  end

  # A live entry moves its address on the button and the question after it.
  defp move_slug(view, slug) do
    view |> element("#artSettings") |> render_change(%{_target: ["slug"], slug: slug})
    view |> element("#artSettings") |> render_submit(%{slug: slug})
    view |> element("#dialog-ok") |> render_click()
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
    assert has_element?(writer, "#slugHint[data-live]")

    move_slug(writer, "")

    assert Articles.get_article!(article.id).slug == nil
    refute has_element?(writer, "#slugHint[data-live]")
    refute has_element?(watcher, "#slugHint[data-live]")
    {:ok, reloaded, _html} = live(conn, ~p"/admin/texts/#{article}")
    assert has_element?(reloaded, "#edSlug")

    move_slug(writer, "restored-doors")

    assert Articles.get_article!(article.id).slug == "restored-doors"
    assert has_element?(writer, ~s(#slugHint[data-live$="/restored-doors"]))
    assert has_element?(watcher, ~s(#slugHint[data-live$="/restored-doors"]))
  end
end
