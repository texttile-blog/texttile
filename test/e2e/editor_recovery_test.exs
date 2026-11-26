defmodule TexttileWeb.E2E.EditorRecoveryTest do
  use TexttileWeb.E2E

  alias Texttile.Articles

  # Leave the old DOM in place, as a sleeping tab does, but let Phoenix
  # know its channel is gone so reconnect runs real form recovery.
  defp disconnect(session) do
    run_script(
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
      """
    )
  end

  defp reconnect(session) do
    session
    |> run_script("() => window.liveSocket.connect()")
    |> await_live()
    |> assert_has(by_css("#tilesBlock[data-ready]"))
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
      |> run_script("document.querySelector('#artSettings').removeAttribute('phx-auto-recover')")
      |> disconnect()

    {:ok, published} = Articles.publish(article, user_fixture())

    conn = reconnect(conn)
    assert Articles.get_article!(article.id).slug == published.slug

    conn =
      conn
      |> assert_has(by_css("#edSlug[value='doors']"))
      |> assert(text(by_css("#stateWord"), "Live"))

    # A deliberate edit on the restored connection still saves normally.
    conn
    |> press(by_css("#edSlug"), "ControlOrMeta+a")
    |> press_sequentially(by_css("#edSlug"), "doors-edited")
    |> click(by_css("#slugSet"))
    |> click(by_css("#dialog-ok"))
    |> assert_has(by_css(~s(#slugHint[data-live$="/doors-edited"])))

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
      |> press(by_css("#edSlug"), "ControlOrMeta+a")
      |> press_sequentially(by_css("#edSlug"), "doors-earlier")
      |> click(by_css("#slugSet"))
      |> click(by_css("#dialog-ok"))
      |> assert_has(by_css(~s(#slugHint[data-live$="/doors-earlier"])))
      |> click(by_css("#stateWord"))
      |> disconnect()

    article = Articles.get_article!(article.id)
    {:ok, _} = Articles.update_settings(article, %{slug: "newer-address"})

    conn = reconnect(conn)
    assert Articles.get_article!(article.id).slug == "newer-address"
    conn |> assert_has(by_css("#edSlug[value='newer-address']"))
  end
end
