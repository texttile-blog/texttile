defmodule TexttileWeb.SettingsLive do
  @moduledoc """
  Settings: what may change while you live with the site, and the
  accounts of everybody who runs it. Nothing here has a Save button:
  every change applies the moment you make it, and the Last-saved line
  keeps itself current. Ported from the round-13 prototype.
  """
  use TexttileWeb, :live_view

  alias Texttile.Accounts
  alias Texttile.Articles
  alias Texttile.Images
  alias Texttile.Markdown
  alias Texttile.Newsletter
  alias Texttile.Settings
  alias Texttile.Uploads

  @note_ms 4600

  # The keys a form on this screen may write. The file-backed keys go
  # through Texttile.Uploads, never through a form.
  @editable ~w(site_title site_description language about_markdown front_page
               posts_per_page theme_css site_visibility site_password
               comments_require_confirmation notify_on_comment
               image_max_edge video_max_edge)

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Settings.subscribe()
      Accounts.subscribe_users()
      Articles.subscribe_admin()
    end

    socket =
      socket
      |> assign(:page_title, "Settings")
      |> assign(:errors, %{})
      |> assign(:confirm_delete, nil)
      |> assign(:confirm_tag, nil)
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
      |> refresh_tags()
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

  # The front-page select speaks under its own name (see the template);
  # it writes the same setting.
  def handle_event(
        "save_setting",
        %{"_target" => ["settings", "front_page_choice"]} = params,
        socket
      ) do
    handle_event(
      "save_setting",
      %{
        "_target" => ["settings", "front_page"],
        "settings" => %{"front_page" => get_in(params, ["settings", "front_page_choice"])}
      },
      socket
    )
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

  # One way out of both questions this screen can ask.
  def handle_event("cancel_delete", _params, socket) do
    {:noreply, socket |> assign(:confirm_delete, nil) |> assign(:confirm_tag, nil)}
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

  ## Tags

  def handle_event("ask_delete_tag", %{"tag" => tag}, socket) do
    {:noreply, assign(socket, :confirm_tag, tag)}
  end

  def handle_event("delete_tag", _params, socket) do
    # nil on a double click: the first click already closed the dialog
    case socket.assigns.confirm_tag do
      nil ->
        {:noreply, socket}

      tag ->
        count = Articles.delete_tag(tag)

        {:noreply,
         socket
         |> assign(:confirm_tag, nil)
         |> refresh_tags()
         |> mark_saved(tag_deleted_note(tag, count))}
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

  # A text changed or went away somewhere in the admin area, so the row
  # of tags may have changed with it. Every other message of the admin
  # topic is about a body, a version or a log, and none of those
  # touches a tag.
  def handle_info({message, _what}, socket)
      when message in [:article_changed, :article_deleted] do
    {:noreply, refresh_tags(socket)}
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

  # The rest of the admin topic: a body, a version, a log. This screen
  # shows none of them.
  def handle_info({_message, _what}, socket), do: {:noreply, socket}

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
          "image_max_edge" => Integer.to_string(settings.image_max_edge),
          "video_max_edge" => Integer.to_string(settings.video_max_edge)
        },
        as: :settings
      )

    socket
    |> assign(:settings, settings)
    |> assign(:settings_form, form)
    |> assign(:about_html, Markdown.to_html(settings.about_markdown))
    |> assign(:pages, Articles.list_pages())
  end

  # The stored choice, only while it still names a published page. A
  # page that disappeared makes the site serve the list again, and the
  # screen says the same instead of claiming another page.
  defp resolved_front_page(settings, pages) do
    with "page:" <> id <- settings.front_page,
         {id, ""} <- Integer.parse(id) do
      Enum.find(pages, &(&1.id == id))
    else
      _ -> nil
    end
  end

  # The page the fixed-front-page radio stands for when clicked: the
  # resolved choice, otherwise the first published page.
  defp fixed_front_page(settings, pages) do
    resolved_front_page(settings, pages) || List.first(pages)
  end

  # The textarea always shows the theme the site wears: the stored one,
  # or the iris default while nothing is stored.
  defp shown_theme_css(""), do: Settings.default_theme_css()
  defp shown_theme_css(css), do: css

  # :online_ids belongs to Admin: assigned on mount, refreshed on every
  # presence diff, so the "here now" marks stay current on their own.
  defp refresh_users(socket) do
    users = Accounts.list_users()
    taken = MapSet.new(users, & &1.username)

    socket
    |> assign(:users, users)
    |> assign(:waiting, Enum.reject(Accounts.admin_usernames(), &MapSet.member?(taken, &1)))
  end

  defp refresh_tags(socket), do: assign(socket, :tags, Articles.tag_counts())

  defp tag_texts(1), do: "1 text"
  defp tag_texts(count), do: "#{count} texts"

  defp tag_deleted_note(tag, 0), do: "No text carried #{tag} any more"
  defp tag_deleted_note(tag, count), do: "#{tag} is off #{tag_texts(count)}"

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

  defp saved_note(:notify_on_comment, true),
    do: "Every new comment travels to everybody with an account here"

  defp saved_note(:notify_on_comment, false), do: "No mail goes out for a comment"

  # The gate only locks with a password in it, so the note tells the
  # truth for both states instead of announcing a protection that is
  # not there yet.
  defp saved_note(:site_visibility, "protected") do
    if Settings.get(:site_password) == "" do
      "Protected once the blog password below is set"
    else
      "The blog waits behind the password now"
    end
  end

  defp saved_note(:site_visibility, "public"), do: "The blog is open to everyone"

  defp saved_note(:site_password, ""), do: "Without a password nothing is protected"

  # A new word is often meant to shut somebody out, and the next text
  # mails it to everybody on the list. This is the moment to say so;
  # the list itself is one click away, under Newsletter.
  defp saved_note(:site_password, _word) do
    count = Newsletter.confirmed_count()

    if Settings.get(:site_visibility) == "protected" and count > 0 do
      "Saved · the next text mails the new word to " <>
        "#{count} #{plural(count, "subscriber", "subscribers")}"
    end
  end

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

  defp notify_note(true) do
    "Everybody with an account here and an address gets one mail per " <>
      "comment: who wrote it, what it says, and the way to it. The mail " <>
      "leaves when the comment stands under the text, so a comment that " <>
      "still waits for its reader mails nobody. The address of the reader " <>
      "is never in it."
  end

  defp notify_note(false) do
    "No mail goes out for a comment. New comments stand on the Comments " <>
      "screen and in the text they belong to."
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
        <%!-- the phone gets the stamp too, short and clipped: the
             hook writes the sentence only where the bar has room --%>
        <span
          class="saved num whitespace-nowrap flex-none max-w-[42vw] md:max-w-none overflow-hidden text-ellipsis"
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
                The admin area itself stays English.
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
            class="boxed"
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
              checked={resolved_front_page(@settings, @pages) == nil}
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
          <label class={[
            "flex gap-[10px] items-start py-3 border-b border-hair",
            @pages == [] && "opacity-60"
          ]}>
            <input
              type="radio"
              name="settings[front_page]"
              value={@pages != [] && "page:#{fixed_front_page(@settings, @pages).id}"}
              checked={resolved_front_page(@settings, @pages) != nil}
              disabled={@pages == []}
              class="w-auto flex-none mt-[3px]"
              style="accent-color:var(--tt-accent)"
            />
            <span>
              <span class="text-[14.5px] font-semibold">A fixed page</span>
              <br />
              <span class="text-[11.5px] text-faint">
                <%= if @pages == [] do %>
                  One of your pages becomes the front door; the text list moves to
                  /texts. There are no pages yet: this choice unlocks with the
                  first one you write.
                <% else %>
                  This page becomes the front door; the text list moves to /texts.
                <% end %>
              </span>
            </span>
          </label>
          <div
            :if={resolved_front_page(@settings, @pages) != nil}
            class="py-3 max-w-[280px]"
            id="front-page-choice"
          >
            <%!-- its own name: with the radios' name, its value would
                 shadow a click back to "Latest texts" --%>
            <label class="lab block mb-[5px]" for="setting-front_page">The page</label>
            <select id="setting-front_page" name="settings[front_page_choice]">
              <option
                :for={page <- @pages}
                value={"page:#{page.id}"}
                selected={@settings.front_page == "page:#{page.id}"}
              >
                {Articles.display_title(page)}
              </option>
            </select>
          </div>
          <div class="drow gtop">
            <label class="lab" for="setting-posts_per_page">Texts a page</label>
            <span class="val">
              <input
                type="number"
                id="setting-posts_per_page"
                name="settings[posts_per_page]"
                value={@settings_form[:posts_per_page].value}
                min="1"
                max="200"
                class="max-w-[110px]"
                phx-debounce="300"
              />
              <div class="hint">
                How many texts the blog list shows before the pager. Between 1
                and 200; the default is 10.
              </div>
              <p :if={@errors[:posts_per_page]} class="text-julia text-[13px] mt-[6px]">
                The value must be {@errors[:posts_per_page]}.
              </p>
            </span>
          </div>
        </.form>

        <.section>Theme</.section>
        <p class="note mb-[10px]">
          Theming is exactly one CSS file, and the admin area and the public
          site both wear it: no theme gallery, no options. The default is
          the iris theme, and this is it below; edit it and this screen
          changes with your next keystroke. Empty the field and the site is
          back in iris.
        </p>
        <.form for={@settings_form} id="theme-form" phx-change="save_setting" phx-hook=".ThemeRefresh">
          <label class="lab block mb-[6px]" for="setting-theme_css">theme.css</label>
          <textarea
            id="setting-theme_css"
            name="settings[theme_css]"
            rows="12"
            spellcheck="false"
            class="boxed font-mono text-[12.5px] leading-[1.65]"
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

        <.section>Access</.section>
        <.form for={@settings_form} id="access-form" phx-change="save_setting">
          <label class="flex gap-[10px] items-start py-3 cursor-pointer border-b border-hair">
            <input
              type="radio"
              name="settings[site_visibility]"
              value="public"
              checked={@settings.site_visibility == "public"}
              class="w-auto flex-none mt-[3px]"
              style="accent-color:var(--tt-accent)"
            />
            <span>
              <span class="text-[14.5px] font-semibold">Public</span>
              <br />
              <span class="text-[11.5px] text-faint">Anyone can read the blog.</span>
            </span>
          </label>
          <label class="flex gap-[10px] items-start py-3 cursor-pointer border-b border-hair">
            <input
              type="radio"
              name="settings[site_visibility]"
              value="protected"
              checked={@settings.site_visibility == "protected"}
              class="w-auto flex-none mt-[3px]"
              style="accent-color:var(--tt-accent)"
            />
            <span>
              <span class="text-[14.5px] font-semibold">Password-protected</span>
              <br />
              <span class="text-[11.5px] text-faint">
                One password for the whole blog, not per text. Readers enter it
                once and are remembered. Admins keep signing in the usual way.
                Search engines see nothing.
              </span>
            </span>
          </label>
          <div class="py-3 max-w-[280px]" id="pwRow">
            <label class="lab block mb-[5px]" for="setting-site_password">Blog password</label>
            <input
              type="text"
              id="setting-site_password"
              name="settings[site_password]"
              value={@settings_form[:site_password].value}
              placeholder="Choose a password"
              phx-debounce="300"
            />
            <div class="hint">
              A shared access word, not a login: it goes into every text mail,
              so everybody on the newsletter list gets it, and you pass it on.
              It is stored as it is written. It is the password of the whole
              blog; without one nothing is protected.
            </div>
          </div>
        </.form>

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
          <label class="opt">
            <input type="hidden" name="settings[notify_on_comment]" value="false" />
            <input
              type="checkbox"
              id="setting-notify_on_comment"
              name="settings[notify_on_comment]"
              value="true"
              checked={@settings.notify_on_comment}
            />
            <span>
              Mail me every new comment
              <span class="note" id="setNotifyNote">
                {notify_note(@settings.notify_on_comment)}
              </span>
            </span>
          </label>
        </.form>

        <.section>Tags</.section>
        <p class="note mb-1 leading-[1.6]">
          Every tag any text carries, and how many carry it. Deleting one
          takes it off all of them at once and closes its archive page. The
          texts themselves stay, and so does everything else they wear.
        </p>
        <div id="tagsList">
          <p :if={@tags == []} class="note">
            No text carries a tag yet. Tags are written beside the text, in
            the settings of the text itself.
          </p>
          <div
            :for={{tag, count} <- @tags}
            class="py-[10px] border-b border-hair flex items-center gap-[10px] flex-wrap"
            id={"tagrow-#{Articles.slugify(tag)}"}
          >
            <b class="text-[14.5px]">{tag}</b>
            <span class="note">{tag_texts(count)}</span>
            <span class="sp"></span>
            <button
              class="btn sm"
              id={"delete-tag-#{Articles.slugify(tag)}"}
              phx-click="ask_delete_tag"
              phx-value-tag={tag}
            >
              Delete
            </button>
          </div>
        </div>

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
            navigate={~p"/admin/profile"}
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

        <.section>Videos</.section>
        <.form for={@settings_form} id="videos-form" phx-change="save_setting">
          <div class="drow">
            <label class="lab" for="setting-video_max_edge">Max longer edge</label>
            <span class="val">
              <span class="addr">
                <input
                  type="number"
                  id="setting-video_max_edge"
                  name="settings[video_max_edge]"
                  value={@settings_form[:video_max_edge].value}
                  min="480"
                  step="80"
                  class="max-w-[120px]"
                  phx-debounce="400"
                />
                <span class="pre">px</span>
              </span>
              <p :if={@errors[:video_max_edge]} class="text-julia text-[13px] mt-[6px]">
                The value must be {@errors[:video_max_edge]}.
              </p>
              <div class="hint">
                An uploaded video is converted once, to one MP4 every browser
                plays, with the longer edge within this; nothing is ever scaled
                up. The original is kept on disk. ffmpeg does the work on one
                thread at the lowest priority, one video at a time, so the site
                stays quick while it runs. A new value applies to what is
                converted after the change; a video already converted keeps the
                file it has.
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

        <.section>Import</.section>
        <p class="note mb-2 leading-[1.6]">
          Texttile imports texts from a zip of bundles: Markdown, settings and
          pictures, made from another system's export. IMPORT.md in the
          repository is the format contract.
        </p>
        <p>
          <.link navigate={~p"/admin/settings/import"} class="btn sm" id="open-import">
            Open the import
          </.link>
        </p>
      </div>

      <.ask
        :if={@confirm_delete}
        heading={"Delete the account of #{Accounts.display_name(@confirm_delete)}?"}
        ok="Delete the account"
        on_ok="delete_user"
        on_cancel="cancel_delete"
      >
        <p>
          <b>{Accounts.display_name(@confirm_delete)}</b>
          can no longer sign in from the moment you confirm, and every
          session open right now ends. What {Accounts.display_name(@confirm_delete)} already wrote stays: the
          texts, the images, the comments and every line of every Log belong
          to the site, not to the account. <br />
          <br /> There is no undo. While the name stands in ADMIN_USERS, its
          owner can sign in again and choose a fresh password.
        </p>
      </.ask>

      <.ask
        :if={@confirm_tag}
        heading={"Delete the tag #{@confirm_tag}?"}
        ok="Delete the tag"
        on_ok="delete_tag"
        on_cancel="cancel_delete"
      >
        <p>
          <b>{@confirm_tag}</b>
          leaves every text that carries it, and /tags/{Articles.slugify(@confirm_tag)} answers nothing from that moment. The texts stay where they are,
          with the rest of their tags. <br />
          <br /> There is no undo. To have the tag back, write it on a text
          again.
        </p>
      </.ask>
    </Layouts.app>
    """
  end

  slot :inner_block, required: true

  defp section(assigns) do
    ~H"""
    <h2 class="set-h">{render_slot(@inner_block)}</h2>
    """
  end
end
