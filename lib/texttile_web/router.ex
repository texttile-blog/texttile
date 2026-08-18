defmodule TexttileWeb.Router do
  use TexttileWeb, :router

  import TexttileWeb.UserAuth

  # Nothing is loaded from outside, so the browser may be told exactly
  # that: every script, style, picture, film and font of this blog comes
  # from this server, and the socket talks back to it. A page that ever
  # tried to reach a third party would break loudly instead of quietly
  # working, which is the point.
  #
  # `style-src` keeps `unsafe-inline`: the markup carries style
  # attributes that name theme variables, and an attribute cannot carry
  # a nonce. `img-src` and `media-src` keep `blob:` for the preview a
  # browser makes of a picture before it is uploaded, and `data:` for
  # the small marks that travel inside the CSS.
  @content_security_policy """
  default-src 'self'; \
  script-src 'self'; \
  style-src 'self' 'unsafe-inline'; \
  img-src 'self' data: blob:; \
  media-src 'self' blob:; \
  font-src 'self'; \
  connect-src 'self'; \
  frame-src 'self'; \
  form-action 'self'; \
  base-uri 'self'; \
  frame-ancestors 'self'; \
  object-src 'none'\
  """

  pipeline :browser do
    plug :accepts, ["html"]
    plug TexttileWeb.Locale
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TexttileWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers, %{"content-security-policy" => @content_security_policy}
    plug :fetch_current_scope_for_user
  end

  # The dashboard and the mailbox write their own scripts into the page.
  # They are development tools, not the product, so they get the header
  # taken off instead of the product getting a looser one.
  pipeline :development_tools do
    plug :delete_content_security_policy
  end

  defp delete_content_security_policy(conn, _opts) do
    Plug.Conn.delete_resp_header(conn, "content-security-policy")
  end

  # Uploaded files and their scaled renditions. Public on purpose; the
  # public site shows them to readers. The theme stylesheet lives here
  # too: every page wears it, signed in or not.
  scope "/", TexttileWeb do
    get "/uploads/*path", UploadsController, :show
    get "/renditions/:edge/*path", UploadsController, :rendition
    get "/theme.css", ThemeController, :show

    # The feed. Outside the gate and outside the session: it answers a
    # reader's program, not a browser, and a guarded blog has none.
    get "/feed.xml", FeedController, :show
  end

  # The backup API: a machine the owner keeps at home pulls the whole
  # installation from here. Outside every browser pipeline, and
  # outside the gate a protected blog puts in front of its readers:
  # this answers a backup client with a token, not a person with a
  # session, and a blog behind a password must still be backed up.
  # TexttileWeb.BackupGate decides who gets an answer at all.
  pipeline :backup do
    plug TexttileWeb.BackupGate
  end

  scope "/backup", TexttileWeb do
    pipe_through :backup

    get "/manifest", BackupController, :manifest
    get "/db", BackupController, :database
    get "/file/:id", BackupController, :file
  end

  # The view counter. It stands outside every browser pipeline on
  # purpose: no session is fetched, no cookie is read or written, and
  # no token is asked for. Counting a page must touch nothing that
  # belongs to the reader.
  scope "/", TexttileWeb do
    post "/count", StatsController, :count
  end

  ## The sign-in family

  scope "/", TexttileWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/login", SessionController, :new
    post "/login", SessionController, :create
  end

  scope "/", TexttileWeb do
    pipe_through :browser

    delete "/logout", SessionController, :delete
    delete "/logout/all", SessionController, :delete_all

    # The mailed link that sets a new password, and the screen that asks
    # for one. Both work signed in or out: a link signs you in as its
    # account.
    get "/forgot", LinkController, :forgot
    post "/forgot", LinkController, :send_link
    get "/link/:token", LinkController, :show
    post "/link/:token", LinkController, :create
  end

  ## The admin area, under /admin: the readers own the root

  scope "/admin", TexttileWeb do
    pipe_through [:browser, :require_authenticated_user]

    # The editor's image uploads: the body holds a token while the file
    # travels here, and the answer is the address the token becomes.
    # The entry is in the address, because an entry takes each picture
    # once and the server has to know whose picture this is.
    post "/texts/:id/images", ImagesController, :create

    # The gallery's uploads: one file per request, the tile queue in
    # the browser feeds them one after the other.
    post "/texts/:id/gallery", GalleryController, :create

    # One entry as a zip: the bundle the import reads, which is a Hugo
    # page bundle as well. Made for the request and gone after it.
    get "/texts/:id/export", ExportController, :show

    # The door of the admin area. The list of entries has an address of
    # its own, so every screen here is a place you can bookmark, and
    # /admin stays the one short way in.
    get "/", AdminController, :index

    live_session :admin,
      on_mount: [
        {TexttileWeb.Locale, :put_locale},
        {TexttileWeb.UserAuth, :ensure_authenticated},
        {TexttileWeb.Admin, :track_presence}
      ] do
      live "/texts", TextsLive
      live "/texts/:id", EditorLive
      live "/comments", CommentsLive
      live "/newsletter", NewsletterLive
      live "/stats", StatsLive
      live "/profile", ProfileLive
      live "/settings", SettingsLive
      live "/settings/import", ImportLive
    end
  end

  # The development tools. They stand before the reader routes: the
  # dashboard has addresses of four segments, like a post, and the last
  # reader route would swallow them.
  if Application.compile_env(:texttile, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:browser, :development_tools]

      live_dashboard "/dashboard", metrics: TexttileWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## The public site

  # The reader pages share a lean root layout without the admin bundle.
  pipeline :site do
    plug :put_root_layout, html: {TexttileWeb.Layouts, :site_root}
  end

  # When the whole blog is protected, a locked reader is sent to the
  # gate; the way back travels along as ?to=.
  pipeline :site_gate do
    plug TexttileWeb.SiteGate
  end

  scope "/", TexttileWeb do
    pipe_through [:browser, :site]

    # The gate itself stays outside the gate.
    get "/unlock", SiteController, :unlock
    post "/unlock", SiteController, :enter_password

    # The mailed confirmation link stays outside too: the reader's
    # comment must not dead-end on a browser that lost the password.
    get "/comments/confirm/:token", SiteController, :confirm_comment

    # The newsletter's mailed links, outside for the same reason. The
    # way off the list is a page with one button: a mail scanner that
    # opens every link must not take anybody off the list.
    get "/newsletter/confirm/:token", SiteController, :confirm_subscriber
    get "/newsletter/unsubscribe/:token", SiteController, :unsubscribe
    post "/newsletter/unsubscribe/:token", SiteController, :do_unsubscribe
  end

  scope "/", TexttileWeb do
    pipe_through [:browser, :site, :site_gate]

    get "/", SiteController, :front
    get "/blog", SiteController, :blog
    get "/tags/:tag", SiteController, :tag

    # An entry that has no slug yet has no address of its own, and a
    # draft carries none until it goes live. This is the door the editor
    # offers until there is one: the reader's page, for admins only.
    get "/preview/:id", SiteController, :preview

    # A reader sends a comment. Behind the gate like the text it is on.
    post "/comments/:article_id", SiteController, :post_comment

    # A reader asks for the newsletter. Behind the gate like the
    # footer form the request comes from.
    post "/newsletter", SiteController, :join_newsletter

    # Every published post lives under the day it went live. Four
    # segments, so no page and no named route can stand in the way.
    get "/:year/:month/:day/:slug", SiteController, :article

    # The catch-all: every published page lives at its slug. Last on
    # purpose; the named routes above win, and the reserved-slug rule
    # in Texttile.Articles keeps texts off those addresses.
    get "/:slug", SiteController, :page
  end
end
