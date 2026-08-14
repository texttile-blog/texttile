defmodule TexttileWeb.E2E.TransportFlowTest do
  @moduledoc """
  The way a screen talks to the server, and what it says when it
  cannot.

  Ten open editors used to go quiet one after another. A slow moment
  pushed one tab onto long polling, the note Phoenix leaves about that
  travelled into every tab opened out of it, and a browser gives one
  site about six connections for all its tabs together. From the
  seventh tab on the pages then waited for each other while looking
  finished: the fields took letters, the buttons took clicks, and
  nothing arrived.
  """

  use TexttileWeb.E2E

  describe "the transport" do
    test "a slow start keeps the WebSocket instead of dropping to long polling", %{conn: conn} do
      # Nine editors starting together on one small machine take longer
      # than the 2.5 s Phoenix throws a working WebSocket away after.
      conn
      |> sign_in()
      |> evaluate(
        "() => window.liveSocket.socket.longPollFallbackMs",
        [is_function: true],
        fn ms ->
          assert ms >= 10_000
        end
      )
      |> evaluate("() => window.liveSocket.socket.transport.name", [is_function: true], fn name ->
        assert name == "WebSocket"
      end)
    end

    test "a fallback another tab wrote down does not travel into this one", %{conn: conn} do
      # A tab opened out of another one inherits its session store, so
      # one slow moment sent every later tab of the day straight to
      # long polling without ever trying a WebSocket.
      {:ok, _} =
        PlaywrightEx.BrowserContext.add_init_script(conn.context_id,
          source: "sessionStorage.setItem('phx:fallback:longpoll', 'true')",
          timeout: 5_000
        )

      conn
      |> sign_in()
      |> evaluate("() => sessionStorage.getItem('phx:fallback:longpoll')", [is_function: true], fn
        note -> assert note in [nil, "null"]
      end)
      |> evaluate("() => window.liveSocket.socket.transport.name", [is_function: true], fn name ->
        assert name == "WebSocket"
      end)
    end
  end

  describe "a screen that is not live" do
    test "says so in the bar instead of swallowing what is typed", %{conn: conn, kb: kb} do
      article = draft!(kb, "A text that loses the line")

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> refute_has("html.phx-late")
      |> refute_has("#stateOffline")
      |> evaluate("() => window.liveSocket.disconnect()", is_function: true)
      # LiveView says this much itself for a line that was there and
      # went. The mark below is the page's own, and it is the one that
      # covers a tab that was never live at all.
      |> assert_has("#stateOffline", text: "Not saved", timeout: 15_000)
      |> assert_has("html.phx-late", timeout: 15_000)
      |> refute_has("#state")
    end
  end

  describe "a line that looks fine" do
    # The socket in the browser stays open when the line is cut without
    # a goodbye, so everything on the screen says the page is live: the
    # transport is a WebSocket, the view wears phx-connected, and every
    # click goes into a line whose other end is gone.
    @cut """
    () => {
      window.liveSocket.socket.conn.send = () => {}
      return window.liveSocket.socket.isConnected()
    }
    """

    test "a page nobody answers any more says so", %{conn: conn, kb: kb} do
      article = draft!(kb, "A text on a line that goes quiet")

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> refute_has("#stateOffline")
      |> evaluate(@cut, [is_function: true], &assert(&1 == true))
      |> assert_has("#stateOffline", text: "Not saved", timeout: 15_000)
      |> assert_has("html[data-line*='quiet']", timeout: 15_000)
    end

    test "and builds the line again, without anybody reloading", %{conn: conn, kb: kb} do
      article = draft!(kb, "A text that gets its line back")

      conn
      |> sign_in()
      |> open_editor(article.id)
      |> evaluate(@cut, [is_function: true], &assert(&1 == true))
      |> assert_has("#stateOffline", timeout: 15_000)
      # nobody reloads and nobody clicks: the page takes the dead line
      # down and builds it again, and says so when it stands.
      |> assert_has("#state", text: "Last saved", timeout: 20_000)
      |> refute_has("html.phx-late")
      # and it is a working line, not a hopeful class: the title goes
      # to the server and comes back in the crumb.
      |> fill_in("Title", with: "The line came back")
      |> assert_has("#crumb", text: "The line came back")
    end
  end
end
