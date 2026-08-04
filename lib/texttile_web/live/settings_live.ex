defmodule TexttileWeb.SettingsLive do
  @moduledoc """
  Settings: what may change while you live with the site, and the
  accounts of everybody who runs it. Nothing here has a Save button:
  every change applies the moment you make it, and the Last-saved line
  keeps itself current. Ported from the round-13 prototype.
  """
  use TexttileWeb, :live_view

  alias Texttile.Accounts
  alias Texttile.Images
  alias Texttile.Markdown
  alias Texttile.Settings
  alias Texttile.Uploads

  @note_ms 4600

  # The keys a form on this screen may write. The file-backed keys go
  # through Texttile.Uploads, never through a form.
  @editable ~w(site_title site_description language about_markdown front_page
               theme_css comments_require_confirmation image_max_edge)

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Settings.subscribe()
      Accounts.subscribe_users()
    end

    socket =
      socket
      |> assign(:page_title, "Settings")
      |> assign(:errors, %{})
      |> assign(:confirm_delete, nil)
      |> allow_upload(:logo,
        accept: ~w(.svg .png .jpg .jpeg .webp),
        max_entries: 1,
        max_file_size: 10_000_000,
        auto_upload: true,
        progress: &handle_upload/3
      )
      |> allow_upload(:favicon,
        accept: ~w(.svg .png .jpg .jpeg .webp),
        max_entries: 1,
        max_file_size: 10_000_000,
        auto_upload: true,
        progress: &handle_upload/3
      )
      |> refresh_settings()
      |> refresh_users()
      |> refresh_storage()
      |> mark_saved(nil)

    {:ok, socket}
  end

  ## Settings that save on change

  def handle_event("save_setting", %{"_target" => ["settings", key]} = params, socket)
      when key in @editable do
    key_atom = String.to_existing_atom(key)
    value = get_in(params, ["settings", key])

    case Settings.put(key_atom, value) do
      {:ok, value} ->
        socket =
          socket
          |> assign(:errors, Map.delete(socket.assigns.errors, key_atom))
          |> refresh_settings()
          |> refresh_storage()
          |> mark_saved(saved_note(key_atom, value))

        # A saved theme is worn at once: the browser refetches the sheet.
        socket =
          if key_atom == :theme_css do
            push_event(socket, "theme_saved", %{})
          else
            socket
          end

        {:noreply, socket}

      {:error, message} ->
        {:noreply, assign(socket, :errors, Map.put(socket.assigns.errors, key_atom, message))}
    end
  end

  def handle_event("save_setting", _params, socket), do: {:noreply, socket}

  ## Logo and favicon

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("reset_mark", %{"mark" => mark}, socket) when mark in ~w(logo favicon) do
    :ok = Uploads.reset_site_mark(String.to_existing_atom(mark))

    {:noreply,
     socket
     |> refresh_settings()
     |> mark_saved("The #{mark} is the Texttile mark again")}
  end

  ## Users

  def handle_event("ask_delete", %{"id" => id}, socket) do
    user = Accounts.get_user(id)

    if is_nil(user) or
         delete_block(user, socket.assigns.users, socket.assigns.current_scope.user) do
      {:noreply, refresh_users(socket)}
    else
      {:noreply, assign(socket, :confirm_delete, user)}
    end
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :confirm_delete, nil)}
  end

  def handle_event("delete_user", _params, socket) do
    # nil on a double click: the first click already closed the dialog
    case socket.assigns.confirm_delete do
      nil ->
        {:noreply, socket}

      user ->
        me = socket.assigns.current_scope.user

        # Every open session of the account is told to disconnect before
        # its rows go, exactly like a password change does it.
        sessions = Accounts.list_sessions(user)

        case Accounts.delete_user(user, by: me) do
          {:ok, _} ->
            Enum.each(
              sessions,
              &TexttileWeb.Endpoint.broadcast(
                TexttileWeb.UserAuth.user_session_topic(&1.token),
                "disconnect",
                %{}
              )
            )

            {:noreply,
             socket
             |> assign(:confirm_delete, nil)
             |> refresh_users()
             |> mark_saved("The account of #{Accounts.display_name(user)} is deleted")}

          {:error, _reason} ->
            # :gone, :last or :yourself: the world moved; show it as it is
            {:noreply, socket |> assign(:confirm_delete, nil) |> refresh_users()}
        end
    end
  end

  ## Storage

  def handle_event("clear_cache", _params, socket) do
    :ok = Images.clear_cache()

    {:noreply,
     socket
     |> refresh_storage()
     |> mark_saved("Image cache cleared · variants regenerate on demand")}
  end

  ## Somebody else changed something

  def handle_info({:setting_changed, _key, _value}, socket) do
    {:noreply, socket |> refresh_settings() |> refresh_storage()}
  end

  def handle_info(:users_changed, socket) do
    socket = refresh_users(socket)

    # An open confirm dialog for an account that no longer exists (or
    # whose facts changed) must not act on a stale struct.
    socket =
      case socket.assigns.confirm_delete do
        nil -> socket
        user -> assign(socket, :confirm_delete, Accounts.get_user(user.id))
      end

    {:noreply, socket}
  end

  ## Uploads arrive through here (auto_upload progress)

  defp handle_upload(mark, entry, socket) do
    if entry.done? do
      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, Uploads.put_site_mark(mark, path, entry.client_name)}
        end)

      case result do
        {:ok, _stored} ->
          {:noreply,
           socket
           |> refresh_settings()
           |> mark_saved("#{mark_label(mark)} uploaded · #{entry.client_name}")}

        {:error, message} ->
          {:noreply, mark_saved(socket, "Not stored · #{message}")}
      end
    else
      {:noreply, socket}
    end
  end

  defp mark_label(:logo), do: "Logo"
  defp mark_label(:favicon), do: "Favicon"

  defp refresh_settings(socket) do
    settings = Settings.all()

    form =
      to_form(
        %{
          "site_title" => settings.site_title,
          "site_description" => settings.site_description,
          "language" => settings.language,
          "about_markdown" => settings.about_markdown,
          "theme_css" => shown_theme_css(settings.theme_css),
          "image_max_edge" => Integer.to_string(settings.image_max_edge)
        },
        as: :settings
      )

    socket
    |> assign(:settings, settings)
    |> assign(:settings_form, form)
    |> assign(:about_html, Markdown.to_html(settings.about_markdown))
  end

  # The textarea always shows the theme the site wears: the stored one,
  # or the iris default while nothing is stored.
  defp shown_theme_css(""), do: Settings.default_theme_css()
  defp shown_theme_css(css), do: css

  # :online_ids belongs to Desk: assigned on mount, refreshed on every
  # presence diff, so the "here now" marks stay current on their own.
  defp refresh_users(socket) do
    users = Accounts.list_users()
    taken = MapSet.new(users, & &1.username)

    socket
    |> assign(:users, users)
    |> assign(:waiting, Enum.reject(Accounts.admin_usernames(), &MapSet.member?(taken, &1)))
  end

  defp refresh_storage(socket) do
    db_path = Texttile.Repo.config()[:database]

    db_bytes =
      case File.stat(db_path) do
        {:ok, stat} -> stat.size
        {:error, _} -> 0
      end

    socket
    |> assign(:uploads_root, Uploads.root())
    |> assign(:db_path, db_path)
    |> assign(:db_size, human_size(db_bytes))
    |> assign(:cache_size, human_size(Images.cache_bytes()))
  end

  defp human_size(bytes) when bytes < 1024 * 1024, do: "#{div(bytes, 1024)} KB"
  defp human_size(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  defp saved_note(:comments_require_confirmation, true),
    do: "Readers confirm their email · new comments wait for the link"

  defp saved_note(:comments_require_confirmation, false),
    do: "Comments appear at once · no confirmation asked"

  defp saved_note(_key, _value), do: nil

  defp mark_saved(socket, note) do
    now = System.system_time(:millisecond)

    socket
    |> assign(:saved_at, now)
    |> assign(:saved_note, note)
    |> assign(:saved_note_until, if(note, do: now + @note_ms))
  end

  # The rules live in Accounts.delete_user_block/3; this screen only
  # puts them into words.
  defp delete_block(user, users, me) do
    case Accounts.delete_user_block(user, me, length(users)) do
      :last -> "The only account left: deleting it would leave nobody who can sign in."
      :yourself -> "This one is you: another admin removes it, not you."
      nil -> nil
    end
  end

  defp user_meta(user) do
    state =
      unless Accounts.admin_username?(user.username), do: "not in ADMIN_USERS · cannot sign in"

    [user.username, user.email, state]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp comments_note(true) do
    "The reader gets one confirmation link per address. The comment stays " <>
      "hidden from readers until the reader follows it, and it carries the " <>
      "mark \"not confirmed yet\" here. Turn this off and every comment " <>
      "appears at once. Spam is filtered invisibly either way: honeypot, " <>
      "timing, rate limit."
  end

  defp comments_note(false) do
    "Every comment appears under the text at once, and nobody confirms " <>
      "anything. Turn this on and a comment waits for the reader to follow " <>
      "a confirmation link. Spam is filtered invisibly either way: honeypot, " <>
      "timing, rate limit."
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      crumb="Settings"
      active="settings"
      others={@others}
    >
      <:bar>
        <span
          class="hidden md:inline text-[12.5px] text-faint num whitespace-nowrap"
          id="savedSettings"
          phx-hook="SavedTicker"
          data-at={@saved_at}
          data-note={@saved_note}
          data-note-until={@saved_note_until}
        >
          Last saved · just now
        </span>
      </:bar>
      <div class="quiet-fields max-w-[760px] mx-auto px-[14px] md:px-6 pt-[22px] md:pt-[30px] pb-[90px]">
        <h1 class="page-h">Settings</h1>
        <p class="lead">
          Everything else is config at install time; this is the part that may
          change while you live with the site. Nothing here has a Save button:
          every change applies the moment you make it.
        </p>

        <.section>Site</.section>
        <.form for={@settings_form} id="site-form" phx-change="save_setting">
          <div class="drow">
            <label class="lab" for="setting-site_title">Site title</label>
            <span class="val">
              <input
                type="text"
                id="setting-site_title"
                name="settings[site_title]"
                value={@settings_form[:site_title].value}
                phx-debounce="300"
              />
            </span>
          </div>
          <div class="drow">
            <label class="lab" for="setting-site_description">Description</label>
            <span class="val">
              <input
                type="text"
                id="setting-site_description"
                name="settings[site_description]"
                value={@settings_form[:site_description].value}
                phx-debounce="300"
              />
            </span>
          </div>
          <div class="drow">
            <label class="lab" for="setting-language">Language</label>
            <span class="val">
              <select id="setting-language" name="settings[language]">
                <option value="en" selected={@settings.language == "en"}>English</option>
                <option value="de" selected={@settings.language == "de"}>Deutsch</option>
                <option value="lt" selected={@settings.language == "lt"}>Lietuvių</option>
              </select>
              <div class="hint">
                For readers: dates, the word "comments", the newsletter emails.
                The desk itself stays English.
              </div>
            </span>
          </div>
        </.form>

        <.section>Logo &amp; favicon</.section>
        <div class="flex items-center gap-3 py-[11px] border-b border-hair">
          <span
            class="w-[42px] h-[42px] flex-none grid place-items-center bg-field rounded"
            id="prev-logo"
          >
            <img
              :if={@settings.logo}
              src={"/uploads/#{@settings.logo}"}
              alt=""
              class="max-w-[30px] max-h-[30px]"
            />
            <Layouts.mark :if={!@settings.logo} size={28} ink="var(--tt-ink)" />
          </span>
          <span class="flex flex-col">
            <b>Logo</b>
            <span class="note" id="name-logo">
              {@settings.logo_name || "Default: the Texttile mark"}
            </span>
            <span class="note">
              The bar here and the public site wear it. SVG, PNG, JPG or WebP;
              a raster file is scaled down on arrival.
            </span>
          </span>
          <span class="sp"></span>
          <button
            :if={@settings.logo}
            class="link"
            id="reset-logo"
            phx-click="reset_mark"
            phx-value-mark="logo"
          >
            Use default
          </button>
          <form id="logo-form" phx-change="validate_upload">
            <label class="btn sm cursor-pointer relative overflow-hidden">
              Upload
              <.live_file_input
                upload={@uploads.logo}
                class="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                aria-label="Upload a logo"
              />
            </label>
          </form>
        </div>
        <div class="flex items-center gap-3 py-[11px] border-b border-hair">
          <span
            class="w-[42px] h-[42px] flex-none grid place-items-center bg-field rounded"
            id="prev-favicon"
          >
            <img
              :if={@settings.favicon}
              src={"/uploads/#{@settings.favicon}"}
              alt=""
              class="max-w-[30px] max-h-[30px]"
            />
            <Layouts.mark :if={!@settings.favicon} size={16} ink="var(--tt-ink)" />
          </span>
          <span class="flex flex-col">
            <b>Favicon</b>
            <span class="note" id="name-favicon">
              {@settings.favicon_name || "Default: the Texttile mark"}
            </span>
            <span class="note">The browser-tab icon. Square SVG, PNG, JPG or WebP.</span>
          </span>
          <span class="sp"></span>
          <button
            :if={@settings.favicon}
            class="link"
            id="reset-favicon"
            phx-click="reset_mark"
            phx-value-mark="favicon"
          >
            Use default
          </button>
          <form id="favicon-form" phx-change="validate_upload">
            <label class="btn sm cursor-pointer relative overflow-hidden">
              Upload
              <.live_file_input
                upload={@uploads.favicon}
                class="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                aria-label="Upload a favicon"
              />
            </label>
          </form>
        </div>

        <.section>About</.section>
        <.form for={@settings_form} id="about-form" phx-change="save_setting">
          <label class="lab block mb-[6px]" for="setting-about_markdown">
            About this blog · Markdown
          </label>
          <textarea
            id="setting-about_markdown"
            name="settings[about_markdown]"
            rows="9"
            spellcheck="false"
            phx-debounce="300"
          >{@settings_form[:about_markdown].value}</textarea>
        </.form>
        <div class="lab mt-[14px]">Preview</div>
        <div class="md-preview text-[13.5px] mt-[10px] pt-3 border-t border-hair" id="aboutPreview">
          {Phoenix.HTML.raw(@about_html)}
        </div>

        <.section>Front page</.section>
        <.form for={@settings_form} id="front-page-form" phx-change="save_setting">
          <label class="flex gap-[10px] items-start py-3 cursor-pointer border-b border-hair">
            <input
              type="radio"
              name="settings[front_page]"
              value="latest"
              checked={@settings.front_page == "latest"}
              class="w-auto flex-none mt-[3px]"
              style="accent-color:var(--tt-accent)"
            />
            <span>
              <span class="text-[14.5px] font-semibold">Latest texts</span>
              <br />
              <span class="text-[11.5px] text-faint">
                Published posts, newest first, each with its preview tile.
              </span>
            </span>
          </label>
          <label class="flex gap-[10px] items-start py-3 border-b border-hair opacity-60">
            <input
              type="radio"
              name="settings[front_page]"
              disabled
              class="w-auto flex-none mt-[3px]"
            />
            <span>
              <span class="text-[14.5px] font-semibold">A fixed page</span>
              <br />
              <span class="text-[11.5px] text-faint">
                One of your pages becomes the front door; the text list moves to
                /texts. There are no pages yet: this choice unlocks with the
                first one you write.
              </span>
            </span>
          </label>
        </.form>

        <.section>Theme</.section>
        <p class="note mb-[10px]">
          Theming is exactly one CSS file, and the desk and the public site
          both wear it: no theme gallery, no options. The default is the iris
          theme, and this is it below; edit it and this screen changes with
          your next keystroke. Empty the field and the site is back in iris.
        </p>
        <.form for={@settings_form} id="theme-form" phx-change="save_setting" phx-hook=".ThemeRefresh">
          <label class="lab block mb-[6px]" for="setting-theme_css">theme.css</label>
          <textarea
            id="setting-theme_css"
            name="settings[theme_css]"
            rows="12"
            spellcheck="false"
            class="font-mono text-[12.5px] leading-[1.65]"
            phx-debounce="300"
          >{@settings_form[:theme_css].value}</textarea>
        </.form>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".ThemeRefresh">
          export default {
            mounted() {
              this.handleEvent("theme_saved", () => {
                const link = document.querySelector('link[href^="/theme.css"]')
                if (link) link.href = "/theme.css?v=" + Date.now()
              })
            }
          }
        </script>

        <.section>Comments</.section>
        <.form for={@settings_form} id="comments-form" phx-change="save_setting">
          <label class="opt">
            <input type="hidden" name="settings[comments_require_confirmation]" value="false" />
            <input
              type="checkbox"
              id="setting-comments_require_confirmation"
              name="settings[comments_require_confirmation]"
              value="true"
              checked={@settings.comments_require_confirmation}
            />
            <span>
              Readers confirm their email before the comment appears
              <span class="note" id="setCmtNote">
                {comments_note(@settings.comments_require_confirmation)}
              </span>
            </span>
          </label>
        </.form>

        <.section>Users</.section>
        <p class="note mb-1 leading-[1.6]">
          Everybody with an account here is an admin, and all admins are
          equal: no roles, no permissions, no owner. The one exception keeps
          you from locking yourself out. Nobody deletes their own account, so
          another admin does that for you. There is no public registration
          either: the ADMIN_USERS setting of this server names everybody who
          may sign in, and each of them chooses a password at the first
          sign-in.
        </p>
        <div id="usersList">
          <div :for={user <- @users} class="py-3 border-b border-hair" id={"user-#{user.id}"}>
            <div class="flex items-center gap-[10px] flex-wrap">
              <b class="text-[14.5px]">{Accounts.display_name(user)}</b>
              <span :if={user.id == @current_scope.user.id} class="note">you</span>
              <span
                :if={
                  user.id != @current_scope.user.id and
                    to_string(user.id) in @online_ids
                }
                class="text-julia text-[12.5px] font-semibold inline-flex items-center gap-[6px]"
              >
                <span class="dot live"></span>here now
              </span>
              <span class="sp"></span>
              <button
                class="btn sm"
                id={"delete-user-#{user.id}"}
                phx-click="ask_delete"
                phx-value-id={user.id}
                disabled={delete_block(user, @users, @current_scope.user) != nil}
              >
                Delete
              </button>
            </div>
            <p class="note mt-[3px]">
              {user_meta(user)}
              <span :if={delete_block(user, @users, @current_scope.user)} class="text-faint">
                · {delete_block(user, @users, @current_scope.user)}
              </span>
            </p>
          </div>
        </div>

        <div class="drow gtop" id="waitingUsers">
          <span class="lab">Not here yet</span>
          <span class="val">
            <p :if={@waiting == []} class="note">
              Every name in ADMIN_USERS has an account.
            </p>
            <p :if={@waiting != []} class="text-[13.5px]">
              {Enum.join(@waiting, ", ")}
            </p>
            <div class="hint">
              These names may sign in but have no account yet. Whoever knows
              such a name opens the site, types it, and chooses a password
              there. To add or remove somebody, change ADMIN_USERS on the
              server. A name you take out loses its access at once.
            </div>
          </span>
        </div>
        <p class="note mt-3">
          Your own displayed name, address and password are on <.link
            navigate={~p"/profile"}
            class="link"
          >your profile</.link>;
          nobody else's password is anywhere in this app.
        </p>

        <.section>Images</.section>
        <.form for={@settings_form} id="images-form" phx-change="save_setting">
          <div class="drow">
            <label class="lab" for="setting-image_max_edge">Max longer edge</label>
            <span class="val">
              <span class="addr">
                <input
                  type="number"
                  id="setting-image_max_edge"
                  name="settings[image_max_edge]"
                  value={@settings_form[:image_max_edge].value}
                  min="800"
                  step="80"
                  class="max-w-[120px]"
                  phx-debounce="400"
                />
                <span class="pre">px</span>
              </span>
              <p :if={@errors[:image_max_edge]} class="text-julia text-[13px] mt-[6px]">
                The value must be {@errors[:image_max_edge]}.
              </p>
              <div class="hint">
                Uploads are scaled down so the longer edge stays within this;
                nothing is ever scaled up. Originals are kept on disk. Display
                sizes are made on the fly when a page first needs them;
                changing this value drops the old cached sizes so nothing
                stale survives.
              </div>
            </span>
          </div>
        </.form>

        <.section>Storage</.section>
        <div class="drow">
          <span class="lab">Images</span>
          <span class="val">
            {@uploads_root} · originals plus cached variants · {@cache_size} cache
          </span>
        </div>
        <div class="drow">
          <span class="lab">Database</span>
          <span class="val">{@db_path} · {@db_size} SQLite</span>
        </div>
        <p class="note mt-3">
          Both paths come from the install config and cannot change while the
          site runs. The backup is the volume; there is no export and no site
          deletion.
        </p>
        <p class="mt-3">
          <button class="btn sm" phx-click="clear_cache">Clear image cache</button>
          <span class="note">Variants regenerate on demand.</span>
        </p>
      </div>

      <div
        :if={@confirm_delete}
        id="scrim"
        class="fixed inset-0 z-[80] grid place-items-center p-5"
        style="background:var(--tt-scrim)"
        phx-window-keydown="cancel_delete"
        phx-key="escape"
      >
        <div
          class="w-[min(430px,100%)] bg-paper px-[22px] pt-5 pb-[18px]"
          style="border-radius:var(--tt-radius-pop); border:1px solid var(--tt-rule); box-shadow: 0 22px 54px rgb(var(--tt-shadow) / .26)"
          role="dialog"
          aria-modal="true"
          aria-labelledby="dlgH"
        >
          <h2 class="font-serif text-[19px] font-semibold tracking-[-.01em]" id="dlgH">
            Delete the account of {Accounts.display_name(@confirm_delete)}?
          </h2>
          <p class="text-[13.5px] text-inksoft mt-[9px] leading-[1.55]">
            <b>{Accounts.display_name(@confirm_delete)}</b>
            can no longer sign in from the moment you confirm, and every
            session open right now ends. What {Accounts.display_name(@confirm_delete)} already wrote stays: the
            texts, the images, the comments and every line of every Log belong
            to the site, not to the account. <br />
            <br /> There is no undo. While the name stands in ADMIN_USERS, its
            owner can sign in again and choose a fresh password.
          </p>
          <div class="flex gap-2 mt-[18px]">
            <button class="btn solid" id="dialog-ok" phx-click="delete_user">
              Delete the account
            </button>
            <button class="btn quiet" id="dialog-cancel" phx-click="cancel_delete">Cancel</button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <h2 class="text-[15px] font-semibold text-ink tracking-[-.01em] mt-9 mb-[13px] pb-2 border-b border-rule">
      {render_slot(@inner_block)}
    </h2>
    """
  end
end
