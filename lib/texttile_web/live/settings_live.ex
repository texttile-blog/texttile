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
  # about_markdown is not among them: it comes from the editor hook,
  # under its own name, and never through a form.
  @editable ~w(site_title site_description language front_page
               posts_per_page theme_css site_visibility site_password
               comments_require_confirmation notify_on_comment
               image_max_edge video_max_edge max_upload_mb
               backup_enabled backup_allowed_ips)

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Settings.subscribe()
      Accounts.subscribe_users()
      Articles.subscribe_admin()
    end

    socket =
      socket
      |> assign(:page_title, gettext("Settings"))
      |> assign(:errors, %{})
      |> assign(:confirm_delete, nil)
      |> assign(:confirm_tag, nil)
      |> assign(:confirm_token, false)
      # The one moment the backup token exists in the clear: from the
      # click that made it to the next thing this screen does.
      |> assign(:backup_token, nil)
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
          # The storage report is not refreshed here: the broadcast
          # this save sends comes back to this tab as well, and
          # handle_info decides there whether the report has to be
          # read again.
          |> mark_saved(saved_note(key_atom, value))

        # A saved theme is worn at once: the browser refetches the sheet.
        socket =
          if key_atom == :theme_css do
            push_event(socket, "theme_saved", %{})
          else
            socket
          end

        # A new language needs the whole page again, not a live step.
        # The shell around this view carries the language too - the
        # lang attribute, and the words the hooks say - and only a
        # fresh request draws that shell. Every other open tab changes
        # over on its next full page.
        if key_atom == :language do
          {:noreply, redirect(socket, to: ~p"/admin/settings")}
        else
          {:noreply, socket}
        end

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

  # The About field is the entry editor with the pictures taken out, so
  # its changes arrive under a name of their own instead of through a
  # form. The field owns its own DOM (phx-update="ignore"), so nothing
  # is written back into it and the caret stays where it was.
  def handle_event("about_changed", %{"text" => text}, socket) do
    {:ok, _} = Settings.put(:about_markdown, text)

    {:noreply,
     socket
     |> assign(:settings, Settings.all())
     |> assign(:about_html, Markdown.to_html(text))
     |> mark_saved(nil)}
  end

  ## Logo and favicon

  def handle_event("validate_upload", _params, socket), do: {:noreply, socket}

  def handle_event("reset_mark", %{"mark" => mark}, socket) when mark in ~w(logo favicon) do
    :ok = Uploads.reset_site_mark(String.to_existing_atom(mark))

    {:noreply,
     socket
     |> refresh_settings()
     |> mark_saved(gettext("The %{mark} is the Texttile mark again", mark: mark))}
  end

  ## Theme

  # Back to the iris default: the stored sheet goes, and the field shows
  # the default again on the next render.
  def handle_event("reset_theme", _params, socket) do
    {:ok, _} = Settings.put(:theme_css, "")

    {:noreply,
     socket
     |> refresh_settings()
     |> push_event("theme_saved", %{})
     |> mark_saved(gettext("The theme is the iris default again"))}
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

  # One way out of every question this screen can ask.
  def handle_event("cancel_delete", _params, socket) do
    {:noreply,
     socket
     |> assign(:confirm_delete, nil)
     |> assign(:confirm_tag, nil)
     |> assign(:confirm_token, false)}
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
             |> mark_saved(
               gettext("The account of %{name} is deleted", name: Accounts.display_name(user))
             )}

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
     |> mark_saved(gettext("Image cache cleared · variants regenerate on demand"))}
  end

  ## Backup

  # The first token of an installation opens nothing that was open
  # before, so it needs no question. Every later one takes the token a
  # backup machine is using out of service, which is why that one asks.
  def handle_event("make_backup_token", _params, socket) do
    {:noreply, shown_token(socket)}
  end

  # The word on the screen goes with the question: from the moment you
  # ask to replace it, the one standing there is the one you are about
  # to take out of service.
  def handle_event("ask_replace_token", _params, socket) do
    {:noreply, socket |> assign(:confirm_token, true) |> assign(:backup_token, nil)}
  end

  def handle_event("replace_backup_token", _params, socket) do
    {:noreply, socket |> assign(:confirm_token, false) |> shown_token()}
  end

  defp shown_token(socket) do
    {:ok, token} = Texttile.Backup.generate_token()

    socket
    |> assign(:backup_token, token)
    |> refresh_settings()
    |> mark_saved(gettext("A backup token is in service · copy it now, it is shown once"))
  end

  ## Somebody else changed something

  # This arrives for a change anybody made, this tab included:
  # Settings.put broadcasts to every subscriber and does not leave the
  # sender out. The storage report walks the whole uploads tree and
  # forks df, so it is read again only for the one setting that moves
  # files. Without that test it ran on every keystroke pause of every
  # field on the screen.
  def handle_info({:setting_changed, key, _value}, socket) do
    socket = refresh_settings(socket)
    {:noreply, if(key == :image_max_edge, do: refresh_storage(socket), else: socket)}
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
           |> mark_saved(
             gettext("%{mark} uploaded · %{file}",
               mark: mark_label(mark),
               file: entry.client_name
             )
           )}

        {:error, message} ->
          {:noreply, mark_saved(socket, gettext("Not stored · %{message}", message: message))}
      end
    else
      {:noreply, socket}
    end
  end

  defp mark_label(:logo), do: gettext("Logo")
  defp mark_label(:favicon), do: gettext("Favicon")

  defp refresh_settings(socket) do
    settings = Settings.all()

    form =
      to_form(
        %{
          "site_title" => settings.site_title,
          "site_description" => settings.site_description,
          "language" => settings.language,
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
    |> assign(:backup_access, Texttile.Backup.last_access())
  end

  defp backup_note(true), do: gettext("· a client with the token may fetch")
  defp backup_note(false), do: gettext("· /backup answers nothing, as if it were not there")

  defp token_state(""), do: gettext("No token yet, so nothing is served")
  defp token_state(_hash), do: gettext("A token is in service, kept as a hash")

  defp last_access_line(nil), do: gettext("Nothing has been fetched yet")

  defp last_access_line(%{at: at, ip: ip}) do
    gettext("%{when} from %{ip}", when: Texttile.I18n.format_moment(at), ip: ip)
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
  defp refresh_users(socket), do: assign(socket, :users, Accounts.list_users())

  # The sizes the select offers. Both grids are rows of cards, and the
  # window decides whether a row holds two, three or four of them, so
  # every size here divides by all three: a page ends with a full row
  # at any width, instead of leaving one card alone at the bottom.
  #
  # A value that came from somewhere else - an older version of this
  # screen, or a hand-written row - stands in the row too, in its
  # place, so opening Settings never silently changes what the blog
  # does.
  @page_sizes [12, 24, 36, 48, 96, 192]

  defp page_sizes(current) do
    if current in @page_sizes, do: @page_sizes, else: Enum.sort([current | @page_sizes])
  end

  defp refresh_tags(socket), do: assign(socket, :tags, Articles.tag_counts())

  defp tag_texts(count), do: ngettext("1 entry", "%{count} entries", count)

  defp tag_deleted_note(tag, 0), do: gettext("No entry carried %{tag} any more", tag: tag)

  defp tag_deleted_note(tag, count),
    do: gettext("%{tag} is off %{entries}", tag: tag, entries: tag_texts(count))

  defp refresh_storage(socket) do
    db_path = Texttile.Repo.config()[:database]

    db_bytes =
      case File.stat(db_path) do
        {:ok, stat} -> stat.size
        {:error, _} -> 0
      end

    usage = Uploads.usage()
    free = Uploads.free_bytes()

    socket
    |> assign(:uploads_root, Uploads.root())
    |> assign(:db_path, db_path)
    |> assign(:db_size, human_size(db_bytes))
    |> assign(:usage, usage)
    |> assign(:usage_files, Enum.sum_by(usage, & &1.files) + 1)
    |> assign(:usage_size, human_size(Enum.sum_by(usage, & &1.bytes) + db_bytes))
    |> assign(:free_size, free && human_size(free))
  end

  # What each folder of the uploads root is for. The layout itself is
  # documented on Texttile.Uploads; this is the one line beside a count.
  defp dir_note("images"), do: gettext("every picture as it came")
  defp dir_note("videos"), do: gettext("every video, and the MP4 ffmpeg made of it")
  defp dir_note("site"), do: gettext("the logo and the favicon")
  defp dir_note("cache"), do: gettext("display sizes, disposable")
  defp dir_note(_dir), do: ""

  @kb 1024
  @mb 1024 * 1024
  @gb 1024 * 1024 * 1024

  defp human_size(bytes) when bytes < @mb, do: gettext("%{size} KB", size: div(bytes, @kb))

  defp human_size(bytes) when bytes < @gb,
    do: gettext("%{size} MB", size: Float.round(bytes / @mb, 1))

  defp human_size(bytes), do: gettext("%{size} GB", size: Float.round(bytes / @gb, 1))

  defp saved_note(:comments_require_confirmation, true),
    do: gettext("Readers confirm their email · new comments wait for the link")

  defp saved_note(:comments_require_confirmation, false),
    do: gettext("Comments appear at once · no confirmation asked")

  defp saved_note(:notify_on_comment, true),
    do: gettext("Every new comment travels to everybody with an account here")

  defp saved_note(:notify_on_comment, false), do: gettext("No mail goes out for a comment")

  # The gate only locks with a password in it, so the note tells the
  # truth for both states instead of announcing a protection that is
  # not there yet.
  defp saved_note(:site_visibility, "protected") do
    if Settings.get(:site_password) == "" do
      gettext("Protected once the blog password below is set")
    else
      gettext("The blog waits behind the password now")
    end
  end

  defp saved_note(:site_visibility, "public"), do: gettext("The blog is open to everyone")

  defp saved_note(:site_password, ""), do: gettext("Without a password nothing is protected")

  # A new word is often meant to shut somebody out, and the next text
  # mails it to everybody on the list. This is the moment to say so;
  # the list itself is one click away, under Newsletter.
  defp saved_note(:site_password, _word) do
    count = Newsletter.confirmed_count()

    if Settings.get(:site_visibility) == "protected" and count > 0 do
      ngettext(
        "Saved · the next entry mails the new word to 1 subscriber",
        "Saved · the next entry mails the new word to %{count} subscribers",
        count
      )
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
      :last -> gettext("The only account left: deleting it would leave nobody who can sign in.")
      :yourself -> gettext("This one is you")
      nil -> nil
    end
  end

  defp user_meta(user) do
    state =
      unless Accounts.admin_username?(user.username),
        do: gettext("not in ADMIN_USERS · cannot sign in")

    [user.username, user.email, state]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
  end

  defp comments_note(true) do
    gettext(
      "The reader gets one confirmation link per address. The comment stays hidden from readers until the reader follows it, and it carries the mark \"not confirmed yet\" here. Turn this off and every comment appears at once. Spam is filtered by honeypot, timing and rate limit checks either way."
    )
  end

  defp comments_note(false) do
    gettext(
      "Every comment appears under the entry at once, and nobody confirms anything. Turn this on and a comment waits for the reader to follow a confirmation link. Spam is filtered by honeypot, timing and rate limit checks either way."
    )
  end

  defp notify_note(true) do
    gettext(
      "Everybody with an account here and an address gets one mail per comment: who wrote it, what it says, and the way to it. The mail leaves when the comment stands under the entry, so a comment that still waits for its reader mails nobody. The address of the reader is never in it."
    )
  end

  defp notify_note(false) do
    gettext(
      "No mail goes out for a comment. New comments stand on the Comments screen and in the entry they belong to."
    )
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      crumb={gettext("Settings")}
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
          {gettext("Last saved · just now")}
        </span>
        <Layouts.view_site />
      </:bar>
      <div class="max-w-[760px] mx-auto px-[14px] md:px-6 pt-[22px] md:pt-[30px] pb-[90px]">
        <h1 class="page-h">{gettext("Settings")}</h1>
        <p class="lead">
          {gettext("Nothing here has a Save button: every change applies the moment you make it.")}
        </p>

        <.section>{gettext("Site")}</.section>
        <%!-- three fields somebody fills in on their first visit here,
             so all three look like fields and not like values --%>
        <.form for={@settings_form} id="site-form" phx-change="save_setting">
          <div class="drow">
            <label class="lab" for="setting-site_title">{gettext("Site title")}</label>
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
            <label class="lab" for="setting-site_description">{gettext("Description")}</label>
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
            <label class="lab" for="setting-language">{gettext("Language")}</label>
            <span class="val">
              <%!-- every language carries the name it calls itself, so
                   the row reads for somebody who cannot read the one
                   the blog is set to right now --%>
              <select id="setting-language" name="settings[language]">
                <option
                  :for={{code, name} <- Texttile.I18n.languages()}
                  value={code}
                  selected={@settings.language == code}
                >
                  {name}
                </option>
              </select>
              <div class="hint">
                {gettext(
                  "The whole blog speaks it: the reader pages, this admin area, the dates and the mails. What you write yourself stays as you wrote it."
                )}
              </div>
            </span>
          </div>
        </.form>

        <.section>{gettext("Logo & favicon")}</.section>
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
            <b>{gettext("Logo")}</b>
            <span class="note" id="name-logo">
              {@settings.logo_name || gettext("Default: the Texttile mark")}
            </span>
            <span class="note">
              {gettext(
                "The bar here and the public site use it. SVG, PNG, JPG or WebP; a raster file is scaled down on arrival to %{px} px on the longer edge.",
                px: Uploads.mark_max_edge()
              )}
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
            {gettext("Use default")}
          </button>
          <form id="logo-form" phx-change="validate_upload">
            <label class="btn sm cursor-pointer relative overflow-hidden">
              {gettext("Upload")}
              <.live_file_input
                upload={@uploads.logo}
                class="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                aria-label={gettext("Upload a logo")}
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
            <b>{gettext("Favicon")}</b>
            <span class="note" id="name-favicon">
              {@settings.favicon_name || gettext("Default: the Texttile mark")}
            </span>
            <span class="note">
              {gettext(
                "The browser-tab icon. Square SVG, PNG, JPG or WebP; a raster file is scaled down on arrival to %{px} px on the longer edge.",
                px: Uploads.mark_max_edge()
              )}
            </span>
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
              {gettext("Upload")}
              <.live_file_input
                upload={@uploads.favicon}
                class="absolute inset-0 w-full h-full opacity-0 cursor-pointer"
                aria-label={gettext("Upload a favicon")}
              />
            </label>
          </form>
        </div>

        <.section>{gettext("About")}</.section>
        <label class="lab block mb-[6px]" for="setting-about_markdown">
          {gettext("About this blog")}
        </label>
        <%!-- the editor of an entry, with the pictures taken out: About
             stands in the band under every page and carries words, not
             a gallery. One hook, one behaviour, one set of keys. --%>
        <.md_bar id="aboutBar" files={false} />
        <div
          id="setting-about_markdown"
          class="ed-body ed-cm boxed-cm"
          phx-hook="BodyEd"
          phx-update="ignore"
          data-event="about_changed"
          data-bar="#aboutBar"
          data-files="false"
          data-label={gettext("About this blog, Markdown")}
          data-placeholder={
            gettext("Who writes here, and what this blog is. Markdown works: ## for a heading.")
          }
        >
          <textarea>{@settings.about_markdown}</textarea>
        </div>
        <div class="lab mt-[14px]">{gettext("Preview")}</div>
        <div class="md-preview text-[13.5px] mt-[10px] pt-3 border-t border-hair" id="aboutPreview">
          {Phoenix.HTML.raw(@about_html)}
        </div>

        <.section>{gettext("Front page")}</.section>
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
              <span class="text-[14.5px] font-semibold">{gettext("Latest entries")}</span>
              <br />
              <span class="text-[11.5px] text-faint">
                {gettext(
                  "The front door sends the reader to /blog: published entries, newest first, each with its preview tile."
                )}
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
              <span class="text-[14.5px] font-semibold">{gettext("A fixed page")}</span>
              <br />
              <span class="text-[11.5px] text-faint">
                <%= if @pages == [] do %>
                  {gettext(
                    "One of your pages becomes the front door. The blog list keeps /blog either way. There are no pages yet: this choice unlocks with the first one you write."
                  )}
                <% else %>
                  {gettext("This page becomes the front door. The blog list keeps /blog either way.")}
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
                 shadow a click back to "Latest entries" --%>
            <label class="lab block mb-[5px]" for="setting-front_page">{gettext("The page")}</label>
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
            <label class="lab" for="setting-posts_per_page">{gettext("Pagination")}</label>
            <span class="val">
              <select
                id="setting-posts_per_page"
                name="settings[posts_per_page]"
                class="max-w-[110px]"
              >
                <option
                  :for={size <- page_sizes(@settings.posts_per_page)}
                  value={size}
                  selected={@settings.posts_per_page == size}
                >
                  {size}
                </option>
              </select>
              <div class="hint">
                {gettext(
                  "How many entries a page holds, on /blog and in Entries. Every size fills whole rows. The default is 12."
                )}
              </div>
              <p :if={@errors[:posts_per_page]} class="text-julia text-[13px] mt-[6px]">
                {gettext("The value must be %{rule}.", rule: @errors[:posts_per_page])}
              </p>
            </span>
          </div>
        </.form>

        <.section>{gettext("Theme")}</.section>
        <p class="note mb-[10px]">
          {gettext("Theming is exactly one CSS file, used for the admin area and the public site.")}
        </p>
        <.form for={@settings_form} id="theme-form" phx-change="save_setting" phx-hook=".ThemeRefresh">
          <span class="labrow">
            <label class="lab" for="setting-theme_css">theme.css</label>
            <%!-- emptying a twelve-row field by hand to get the default
                 back is no way to ask for it --%>
            <button
              :if={@settings.theme_css != ""}
              type="button"
              class="link"
              id="reset-theme"
              phx-click="reset_theme"
            >
              {gettext("Reset")}
            </button>
          </span>
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

        <.section>{gettext("Access")}</.section>
        <%!-- Two choices and the field that belongs to the second one.
             No rules between them: they are one question, not three
             rows of a list, and a line under the last choice cut the
             password field away from the word it serves. The field is
             indented to the text column of the choices instead, so it
             reads as what "Password-protected" needs. The radios carry
             a size of their own, so that indent is one number and not
             a browser's idea of a radio. --%>
        <.form for={@settings_form} id="access-form" phx-change="save_setting">
          <label class="flex gap-[10px] items-start py-3 cursor-pointer">
            <input
              type="radio"
              name="settings[site_visibility]"
              value="public"
              checked={@settings.site_visibility == "public"}
              class="w-[13px] h-[13px] flex-none mt-[3px]"
              style="accent-color:var(--tt-accent)"
            />
            <span>
              <span class="text-[14.5px] font-semibold">{gettext("Public")}</span>
              <br />
              <span class="text-[11.5px] text-faint">{gettext("Anyone can read the blog.")}</span>
            </span>
          </label>
          <label class="flex gap-[10px] items-start py-3 cursor-pointer">
            <input
              type="radio"
              name="settings[site_visibility]"
              value="protected"
              checked={@settings.site_visibility == "protected"}
              class="w-[13px] h-[13px] flex-none mt-[3px]"
              style="accent-color:var(--tt-accent)"
            />
            <span>
              <span class="text-[14.5px] font-semibold">{gettext("Password-protected")}</span>
              <br />
              <span class="text-[11.5px] text-faint">
                {gettext(
                  "One password for the whole blog. Readers enter it once and are remembered. Search engines see nothing."
                )}
              </span>
            </span>
          </label>
          <%!-- the field is short, the sentence under it is not: the
               hint keeps the width of the column --%>
          <div class="pl-[23px] pb-3" id="pwRow">
            <label class="lab block mb-[5px]" for="setting-site_password">
              {gettext("Blog password")}
            </label>
            <input
              type="text"
              id="setting-site_password"
              name="settings[site_password]"
              value={@settings_form[:site_password].value}
              placeholder={gettext("Choose a password")}
              phx-debounce="300"
              class="max-w-[280px]"
            />
            <div class="hint">
              {gettext(
                "A shared access word, not a login: it goes into every entry mail, so everybody on the newsletter list gets it, and you pass it on. It is stored as it is written. It is the password of the whole blog; without one nothing is protected."
              )}
            </div>
          </div>
        </.form>

        <.section>{gettext("Comments")}</.section>
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
              {gettext("Readers confirm their email before the comment appears")}
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
              {gettext("Mail me every new comment")}
              <span class="note" id="setNotifyNote">
                {notify_note(@settings.notify_on_comment)}
              </span>
            </span>
          </label>
        </.form>

        <.section>{gettext("Tags")}</.section>
        <p class="note mb-1 leading-[1.6]">
          {gettext(
            "Every tag any entry carries. Deleting one takes it off all of them at once and closes its archive page. The entries themselves stay, and so do all the other tags."
          )}
        </p>
        <div id="tagsList">
          <p :if={@tags == []} class="note">
            {gettext(
              "No entry carries a tag yet. Tags are written beside the entry, in the settings of the entry itself."
            )}
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
              {gettext("Delete")}
            </button>
          </div>
        </div>

        <.section>{gettext("Users")}</.section>
        <p class="note mb-1 leading-[1.6]">
          {gettext(
            "There is no registration: the ADMIN_USERS setting of this server names everybody who may sign in, and each of them chooses a password at the first sign-in. Everybody with an account here is an admin, and all admins are equal: no roles, no permissions."
          )}
        </p>
        <div id="usersList">
          <div :for={user <- @users} class="py-3 border-b border-hair" id={"user-#{user.id}"}>
            <div class="flex items-center gap-[10px] flex-wrap">
              <b class="text-[14.5px]">{Accounts.display_name(user)}</b>
              <span :if={user.id == @current_scope.user.id} class="note">{gettext("you")}</span>
              <span
                :if={
                  user.id != @current_scope.user.id and
                    to_string(user.id) in @online_ids
                }
                class="text-julia text-[12.5px] font-semibold inline-flex items-center gap-[6px]"
              >
                <span class="dot live"></span>{gettext("here now")}
              </span>
              <span class="sp"></span>
              <button
                class="btn sm"
                id={"delete-user-#{user.id}"}
                phx-click="ask_delete"
                phx-value-id={user.id}
                disabled={delete_block(user, @users, @current_scope.user) != nil}
              >
                {gettext("Delete")}
              </button>
            </div>
            <%!-- why the Delete is off, if it is. It is the one thing
                 on the row that is not a fact about the account, so it
                 carries the colour that means "read this". --%>
            <p class="note mt-[3px]">
              {user_meta(user)}
              <span :if={delete_block(user, @users, @current_scope.user)} class="text-julia">
                · {delete_block(user, @users, @current_scope.user)}
              </span>
            </p>
          </div>
        </div>

        <p class="note mt-3">
          {gettext("Change your own displayed name, address and password on")}
          <.link navigate={~p"/admin/profile"} class="link">{gettext("your profile")}</.link>.
        </p>

        <.section>{gettext("Images")}</.section>
        <.form for={@settings_form} id="images-form" phx-change="save_setting">
          <div class="drow">
            <label class="lab" for="setting-image_max_edge">{gettext("Max longer edge")}</label>
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
                {gettext("The value must be %{rule}.", rule: @errors[:image_max_edge])}
              </p>
              <div class="hint">
                {gettext(
                  "Uploads are scaled down so the longer edge stays within this; nothing is ever scaled up. Originals are kept on disk. Display sizes are made on the fly when a page first needs them; changing this value drops the old cached sizes so nothing stale survives."
                )}
              </div>
            </span>
          </div>
        </.form>

        <.section>{gettext("Videos")}</.section>
        <.form for={@settings_form} id="videos-form" phx-change="save_setting">
          <div class="drow">
            <label class="lab" for="setting-video_max_edge">{gettext("Max longer edge")}</label>
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
                {gettext("The value must be %{rule}.", rule: @errors[:video_max_edge])}
              </p>
              <div class="hint">
                {gettext(
                  "An uploaded video is converted once, to one MP4 every browser plays, with the longer edge within this; nothing is ever scaled up. The original is kept on disk. ffmpeg does the work on one thread at the lowest priority, one video at a time, so the site stays quick while it runs. A new value applies to what is converted after the change; a video already converted keeps the file it has."
                )}
              </div>
            </span>
          </div>
        </.form>

        <.section>{gettext("Storage")}</.section>
        <.form for={@settings_form} id="upload-form" phx-change="save_setting">
          <div class="drow">
            <label class="lab" for="setting-max_upload_mb">{gettext("Biggest upload")}</label>
            <span class="val">
              <span class="flex items-baseline gap-[7px]">
                <input
                  type="number"
                  id="setting-max_upload_mb"
                  name="settings[max_upload_mb]"
                  value={@settings.max_upload_mb}
                  min="10"
                  max="2048"
                  step="1"
                  phx-debounce="500"
                  class="max-w-[110px]"
                />
                <span class="note">{gettext("MB")}</span>
              </span>
              <p :if={@errors[:max_upload_mb]} class="text-julia text-[13px] mt-[6px]">
                {gettext("The value must be %{rule}.", rule: @errors[:max_upload_mb])}
              </p>
            </span>
            <div class="hint">
              {gettext(
                "One roof for a picture and for a video. The browser turns a bigger file away before it is uploaded, and the server stops reading one that arrives anyway. A phone film of a few minutes weighs a few hundred MB."
              )}
            </div>
          </div>
        </.form>

        <%!-- What is on the volume, folder by folder, and what is left
             of it. The counts are walked on every render of this
             screen, which one person opens now and then. --%>
        <div class="drow">
          <span class="lab">{gettext("What lies on the volume")}</span>
          <span class="val">
            <table class="tally" id="storageTally">
              <thead>
                <tr>
                  <th>{gettext("Folder")}</th>
                  <th class="n">{gettext("Files")}</th>
                  <th class="n">{gettext("Size")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @usage} id={"usage-#{row.dir}"}>
                  <td>
                    <span class="p">{row.dir}/</span>
                    <span class="note">{dir_note(row.dir)}</span>
                  </td>
                  <td class="n num">{row.files}</td>
                  <td class="n num">{human_size(row.bytes)}</td>
                </tr>
                <tr id="usage-db">
                  <td>
                    <span class="p">{Path.basename(@db_path)}</span>
                    <span class="note">{gettext("the database, one SQLite file")}</span>
                  </td>
                  <td class="n num">1</td>
                  <td class="n num">{@db_size}</td>
                </tr>
              </tbody>
              <tfoot>
                <tr id="usage-total">
                  <td>{gettext("Together")}</td>
                  <td class="n num">{@usage_files}</td>
                  <td class="n num">{@usage_size}</td>
                </tr>
                <tr :if={@free_size} id="usage-free">
                  <td>{gettext("Free on this volume")}</td>
                  <td></td>
                  <td class="n num">{@free_size}</td>
                </tr>
              </tfoot>
            </table>
          </span>
          <div class="hint">
            {gettext("The uploads stand below %{root} and the database is %{db}.",
              root: @uploads_root,
              db: @db_path
            )}
            {gettext(
              "Both paths come from the install config and cannot change while the site runs. The volume is the whole installation; a copy of it is a copy of the site."
            )}
          </div>
        </div>
        <p class="mt-3">
          <button class="btn sm" phx-click="clear_cache">Clear image cache</button>
          <span class="note">Variants regenerate on demand.</span>
        </p>

        <.section>{gettext("Backup")}</.section>
        <div id="backupSection">
          <p class="note mb-2 leading-[1.6]">
            {gettext(
              "A machine you keep fetches the database and every uploaded file from here, on a clock of its own. It holds the token and this server holds nothing of it, so whoever breaks in here finds no way to your copies. The client is scripts/texttile-backup.sh in the repository, and where it puts the copies is as worth guarding as this blog."
            )}
          </p>

          <.form for={@settings_form} id="backup-form" phx-change="save_setting">
            <label class="opt">
              <input type="hidden" name="settings[backup_enabled]" value="false" />
              <input
                type="checkbox"
                id="setting-backup_enabled"
                name="settings[backup_enabled]"
                value="true"
                checked={@settings.backup_enabled}
              />
              <span>
                {gettext("Serve a backup client at /backup")}
                <span class="note" id="setBackupNote">
                  {backup_note(@settings.backup_enabled)}
                </span>
              </span>
            </label>
          </.form>

          <%!-- The word is shown once and has to reach a configuration
               file somewhere else, so it is handed over the way the
               editor hands over the lines of an entry: touching it
               picks all of it, and Copy says what it did. --%>
          <div class="drow" id="backupTokenRow" phx-hook="CopyOut">
            <span class="labrow">
              <span class="lab">{gettext("Token")}</span>
              <button
                :if={@backup_token}
                type="button"
                class="link"
                id="copyBackupToken"
                data-copy
              >
                {gettext("Copy")}
              </button>
            </span>
            <span class="val">
              <%= if @backup_token do %>
                <textarea
                  id="backupToken"
                  class="sharelines block break-all bg-wash px-[10px] py-2 text-[12.5px] leading-[1.5]"
                  style="border-radius: var(--tt-radius); border: 1px solid var(--tt-rule)"
                  readonly
                  spellcheck="false"
                  aria-label={gettext("The backup token")}
                >{@backup_token}</textarea>
                <p class="note mt-[6px]">
                  {gettext(
                    "Write it into the configuration of your backup machine now. It is never shown again."
                  )}
                </p>
              <% else %>
                <span class="note" id="backupTokenState">
                  {token_state(@settings.backup_token_hash)}
                </span>
              <% end %>
              <p class="mt-2">
                <button
                  :if={@settings.backup_token_hash == ""}
                  type="button"
                  class="btn sm"
                  id="makeBackupToken"
                  phx-click="make_backup_token"
                >
                  {gettext("Create a token")}
                </button>
                <button
                  :if={@settings.backup_token_hash != ""}
                  type="button"
                  class="btn sm"
                  id="replaceBackupToken"
                  phx-click="ask_replace_token"
                >
                  {gettext("Replace the token")}
                </button>
              </p>
            </span>
            <div class="hint">
              {gettext(
                "It opens the backup endpoints and nothing else, and it only ever reads. Keep it like a password all the same: what it fetches is the database, and the database carries the blog password, the sign-in of every account and the address of every reader who wrote to you."
              )}
            </div>
          </div>

          <.form for={@settings_form} id="backup-ips-form" phx-change="save_setting">
            <div class="drow">
              <label class="lab" for="setting-backup_allowed_ips">
                {gettext("Only these addresses")}
              </label>
              <span class="val">
                <input
                  type="text"
                  id="setting-backup_allowed_ips"
                  name="settings[backup_allowed_ips]"
                  value={@settings.backup_allowed_ips}
                  placeholder={gettext("Any address")}
                  phx-debounce="500"
                  class="max-w-[280px]"
                />
                <p :if={@errors[:backup_allowed_ips]} class="text-julia text-[13px] mt-[6px]">
                  {@errors[:backup_allowed_ips]}
                </p>
              </span>
              <div class="hint">
                {gettext(
                  "The addresses your backup machine calls from, separated by commas. Empty is the usual case: then the token alone decides. Behind a proxy this is only as good as the header the proxy writes, so read it as a second lock and never as the first."
                )}
              </div>
            </div>
          </.form>

          <div class="drow">
            <span class="lab">{gettext("Last fetched")}</span>
            <span class="val" id="backupLastAccess">{last_access_line(@backup_access)}</span>
            <div class="hint">
              {gettext(
                "A backup that stopped running says nothing until the day you need it. This line is where it shows."
              )}
            </div>
          </div>
        </div>

        <.section>{gettext("Import")}</.section>
        <p class="note mb-2 leading-[1.6]">
          {gettext(
            "Texttile imports entries from a zip of bundles: Markdown, settings and pictures, made from another systems export."
          )}
          <.import_doc />
          {gettext("in the repository is the format contract.")}
        </p>
        <p>
          <.link navigate={~p"/admin/settings/import"} class="btn sm" id="open-import">
            {gettext("Open the import")}
          </.link>
        </p>

        <%!-- Which build runs. The number stays behind the sign-in:
             a public version tells an attacker which holes to try. --%>
        <.section>{gettext("Version")}</.section>
        <div class="drow">
          <span class="lab">{gettext("This installation")}</span>
          <span class="val num" id="appVersion">{Texttile.version()}</span>
          <div class="hint">
            {gettext(
              "Every change to Texttile raises this number: the last of the three for a repair, the middle one for something new, the first one when an old habit breaks. Name it when you report a problem, because it says which build stands here."
            )}
          </div>
        </div>
      </div>

      <.ask
        :if={@confirm_delete}
        heading={
          gettext("Delete the account of %{name}?", name: Accounts.display_name(@confirm_delete))
        }
        ok={gettext("Delete the account")}
        on_ok="delete_user"
        on_cancel="cancel_delete"
      >
        <p>
          <b>{Accounts.display_name(@confirm_delete)}</b>
          {gettext(
            "can no longer sign in from the moment you confirm, and every session open right now ends. What %{name} already wrote stays: the entries, the images, the comments and every line of every Log belong to the site, not to the account.",
            name: Accounts.display_name(@confirm_delete)
          )}
          <br />
          <br />
          {gettext(
            "There is no undo. While the name stands in ADMIN_USERS, its owner can sign in again and choose a fresh password."
          )}
        </p>
      </.ask>

      <.ask
        :if={@confirm_token}
        heading={gettext("Replace the backup token?")}
        ok={gettext("Replace it")}
        on_ok="replace_backup_token"
        on_cancel="cancel_delete"
      >
        <p>
          {gettext(
            "The token in service stops opening anything the moment you confirm, and your backup machine gets nothing until you write the new one into its configuration."
          )}
          <br />
          <br />
          {gettext(
            "Do this when a token may have got out, and after that whenever you like: the copies you already keep are untouched by it."
          )}
        </p>
      </.ask>

      <.ask
        :if={@confirm_tag}
        heading={gettext("Delete the tag %{tag}?", tag: @confirm_tag)}
        ok={gettext("Delete the tag")}
        on_ok="delete_tag"
        on_cancel="cancel_delete"
      >
        <p>
          <b>{@confirm_tag}</b>
          {gettext(
            "leaves every entry that carries it, and /tags/%{slug} answers nothing from that moment. The entries stay where they are, with the rest of their tags.",
            slug: Articles.slugify(@confirm_tag)
          )}
          <br />
          <br />
          {gettext("There is no undo. To have the tag back, write it on an entry again.")}
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
