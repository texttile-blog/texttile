defmodule TexttileWeb.Router do
  use TexttileWeb, :router

  import TexttileWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TexttileWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  # Uploaded files: the site marks now, the images of the texts later.
  # Public on purpose; the public site shows them to readers. The theme
  # stylesheet lives here too: every page wears it, signed in or not.
  scope "/", TexttileWeb do
    get "/uploads/*path", UploadsController, :show
    get "/theme.css", ThemeController, :show
  end

  ## The sign-in family

  scope "/", TexttileWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    post "/login/claim", SessionController, :claim
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

  ## The desk

  scope "/", TexttileWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :desk,
      on_mount: [
        {TexttileWeb.UserAuth, :ensure_authenticated},
        {TexttileWeb.Desk, :track_presence}
      ] do
      live "/", TextsLive
      live "/texts/:id", EditorLive
      live "/profile", ProfileLive
      live "/settings", SettingsLive
    end
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:texttile, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TexttileWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
