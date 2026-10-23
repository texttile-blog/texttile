defmodule TexttileWeb.E2E.EditorRecoveryTest do
  use TexttileWeb.E2E

  alias Texttile.Articles

  # Leave the old DOM in place, as a sleeping tab does, but let Phoenix
  # know its channel is gone so reconnect runs real form recovery.
  defp disconnect(session) do
    evaluate(
      session,
      """
      () => new Promise(resolve => {
        window.liveSocket.disconnect(() => {
          window.liveSocket.socket.channels
            .filter(channel => channel.state === "joined")
            .forEach(channel => channel.trigger("phx_error"))
          resolve(true)
        })
      })
      """,
      is_function: true
    )
  end

  defp reconnect(session) do
    session
    |> evaluate("() => window.liveSocket.connect()", is_function: true)
    |> await_live()
    |> assert_has("#tilesBlock[data-ready]")
  end

  test "a sleeping draft tab cannot erase the address published by another admin", %{
    conn: conn,
    kb: kb
  } do
    article = draft!(kb, "Doors")

    conn =
      conn
      |> sign_in()
      |> open_editor(article.id)
      # A tab opened before the fix has no custom recovery binding yet.
      |> evaluate("document.querySelector('#artSettings').removeAttribute('phx-auto-recover')")
      |> disconnect()

    {:ok, published} = Articles.publish(article, user_fixture())

    conn = reconnect(conn)
    assert Articles.get_article!(article.id).slug == published.slug

    conn =
      conn
      |> assert_has("#edSlug[value='doors']")
      |> assert_has("#stateWord", text: "Published")

    # A deliberate edit on the restored connection still saves normally.
    conn
    |> press("#edSlug", "ControlOrMeta+a")
    |> type("#edSlug", "doors-edited")
    |> assert_has("#slugHint", text: "doors-edited is live")

    assert Articles.get_article!(article.id).slug == "doors-edited"
  end

  test "reconnect does not replay a previously edited address over a newer saved address", %{
    conn: conn,
    kb: kb
  } do
    article = draft!(kb, "Doors")
    {:ok, article} = Articles.publish(article, kb)

    conn =
      conn
      |> sign_in()
      |> open_editor(article.id)
      |> press("#edSlug", "ControlOrMeta+a")
      |> type("#edSlug", "doors-earlier")
      |> assert_has("#slugHint", text: "doors-earlier is live")
      |> click("#stateWord")
      |> disconnect()

    article = Articles.get_article!(article.id)
    {:ok, _} = Articles.update_settings(article, %{slug: "newer-address"})

    conn = reconnect(conn)
    assert Articles.get_article!(article.id).slug == "newer-address"
    conn |> assert_has("#edSlug[value='newer-address']")
  end
end
