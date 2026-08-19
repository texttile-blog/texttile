defmodule TexttileWeb.E2E.TransportFlowTest do
  @moduledoc """
  The way a screen talks to the server, and what it says when it
  cannot.

  Ten open editors used to go quiet one after another. A slow moment
  pushed one tab onto long polling, the note Phoenix leaves about that
  travelled into every tab opened out of it, and over HTTP/1.1 a
  browser gives one site about six connections for all its tabs
  together. From the seventh tab on the pages then waited for each
  other while looking finished: the fields took letters, the buttons
  took clicks, and nothing arrived. That last part belongs to HTTP/1.1,
  which is the development server; a site on HTTPS shares one HTTP/2
  connection between all its polls, and ten such tabs were measured
  against the real machine without one going quiet.

  A tab can go quiet on a WebSocket too, and that is what the last
  group here is about: a line that was cut without a goodbye stays open
  in the browser, and nothing on the screen changes until somebody
  asks.
  """

  use TexttileWeb.E2E

  alias Texttile.Articles

  # The watch counts in seconds a reader would not notice: four to the
  # next question, eight of silence before the line is called quiet,
  # ten before it is built again. A test that sits through those spends
  # three quarters of a minute waiting for clocks, so it sets its own
  # before the page scripts run. The mechanism under test is the same
  # one, only faster.
  @fast_clocks "window.__lineTiming = {tick: 500, ask: 400, quiet: 1200, revive: 1000, late: 400}"

  defp fast_clocks(conn) do
    {:ok, _} =
      PlaywrightEx.BrowserContext.add_init_script(conn.context_id,
        source: @fast_clocks,
        timeout: 5_000
      )

    conn
  end

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
      |> fast_clocks()
      |> sign_in()
      |> open_editor(article.id)
      |> refute_has("html.phx-late")
      |> refute_has("#stateOffline")
      |> evaluate("() => window.liveSocket.disconnect()", is_function: true)
      # LiveView says this much itself for a line that was there and
      # went. The mark below is the page's own, and it is the one that
      # covers a tab that was never live at all.
      |> assert_has("#stateOffline", text: "Not saved", timeout: 5_000)
      |> assert_has("html.phx-late", timeout: 5_000)
      |> refute_has("#state")
    end
  end

  describe "a line that looks fine" do
    # The socket in the browser stays open when the line is cut without
    # a goodbye, so everything on the screen says the page is live: the
    # transport is a WebSocket, the view wears phx-connected, and every
    # click goes into a line whose other end is gone.
    #
    # Anything pushed into that line is answered by LiveView half a
    # minute later with a rejected promise, which the browser reports as
    # an error on the page. That is the line's own doing and not a
    # defect under test, and the test driver crashes on the shape of it
    # (`String.Chars not implemented for Map`), taking every later
    # browser test with it. So the page keeps that one complaint to
    # itself.
    @cut """
    () => {
      window.addEventListener("unhandledrejection", e => e.preventDefault())
      window.liveSocket.socket.conn.send = () => {}
      return window.liveSocket.socket.isConnected()
    }
    """

    test "a page nobody answers any more says so", %{conn: conn, kb: kb} do
      article = draft!(kb, "A text on a line that goes quiet")

      conn
      |> fast_clocks()
      |> sign_in()
      |> open_editor(article.id)
      |> refute_has("#stateOffline")
      |> evaluate(@cut, [is_function: true], &assert(&1 == true))
      |> assert_has("#stateOffline", text: "Not saved", timeout: 5_000)
      |> assert_has("html[data-line*='quiet']", timeout: 5_000)
    end

    test "and builds the line again, without anybody reloading", %{conn: conn, kb: kb} do
      article = draft!(kb, "A text that gets its line back")

      conn
      |> fast_clocks()
      |> sign_in()
      |> open_editor(article.id)
      |> evaluate(@cut, [is_function: true], &assert(&1 == true))
      |> assert_has("#stateOffline", timeout: 5_000)
      # nobody reloads and nobody clicks: the page takes the dead line
      # down and builds it again, and says so when it stands.
      |> assert_has("#state", text: "Last saved", timeout: 10_000)
      |> refute_has("html.phx-late")
      # the record names an answer, not a hopeful class: the new line
      # was asked and it replied.
      |> assert_has("html[data-line*='answered']")
      # and it is a working line, not a hopeful class: the title goes
      # to the server and comes back in the crumb.
      |> fill_in("Title", with: "The line came back")
      |> assert_has("#crumb", text: "The line came back")
    end

    test "words written into a quiet line are still there afterwards", %{conn: conn, kb: kb} do
      article = draft!(kb, "A text written on a quiet line", "")

      conn =
        conn
        |> fast_clocks()
        |> sign_in()
        |> open_editor(article.id)
        |> type(".ed-cm .cm-content", "Before the line went")

      eventually(fn -> Articles.get_article!(article.id).body =~ "Before" end)

      # Everything written from here reaches nobody. Without the watch,
      # LiveView answers that half a minute later with a hard refresh,
      # and a refresh throws these words away.
      conn
      |> evaluate(@cut, [is_function: true], &assert(&1 == true))
      |> type(".ed-cm .cm-content", " and after it went")
      |> assert_has("#stateOffline", timeout: 5_000)
      |> assert_has("#state", text: "Last saved", timeout: 10_000)
      |> assert_has(".ed-cm", text: "Before the line went and after it went")
      # one more keystroke on the line that stands, and the words that
      # were written into the quiet are on the server too
      |> type(".ed-cm .cm-content", ".")

      eventually(fn ->
        Articles.get_article!(article.id).body =~ "Before the line went and after it went."
      end)
    end
  end

  describe "a tab that comes back from the cache" do
    # A page put into the browser's back-forward cache loses its socket
    # there, and Phoenix is told to expect that, so it silences the
    # close: no error reaches the channels, and they go on believing
    # they are joined. The socket is built again when the page comes
    # back, so everything reads healthy - the transport is a WebSocket,
    # the ping answers in milliseconds, the bar says the last save.
    #
    # The server keeps a view with the connection it arrived on, and
    # threw this one away with the connection that went. Every click
    # since then is answered with "unmatched topic": answered, and
    # answered with nothing.
    @stale """
    () => {
      const socket = window.liveSocket.socket
      socket.conn.onclose = () => {}
      socket.conn.close()
      socket.conn = null
      socket.connect()
      return window.liveSocket.main.channel.state
    }
    """

    test "a view the server threw away is joined again", %{conn: conn, kb: kb} do
      article = draft!(kb, "A text in a tab that was put aside")

      conn
      |> fast_clocks()
      |> sign_in()
      |> open_editor(article.id)
      # the channel still says joined, which is the whole trap
      |> evaluate(@stale, [is_function: true], &assert(&1 == "joined"))
      # nobody reloads: the page notices that its view cannot be the one
      # on this line, and joins again. The title proves it, because a
      # crumb only changes when the server answered.
      |> fill_in("Title", with: "A tab that came back")
      |> assert_has("#crumb", text: "A tab that came back", timeout: 10_000)
      |> assert_has("#state", text: "Last saved", timeout: 10_000)
    end
  end
end
