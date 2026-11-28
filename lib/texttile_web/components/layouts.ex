defmodule TexttileWeb.Layouts do
  @moduledoc """
  The two shells of the app: `app/1` is the admin area (topbar with
  the wordmark menu), `auth/1` is the one column the sign-in family shares.
  The design comes from the round-13 prototype.
  """
  use TexttileWeb, :html

  embed_templates "layouts/*"

  @doc """
  The mark of the app: three full lines of text, one short one, and the
  row of tiles under it, the last of them in the accent.
  """
  attr :size, :integer, default: 21
  attr :ink, :string, default: "currentColor"

  def mark(assigns) do
    ~H"""
    <svg width={@size} height={@size} viewBox="0 0 43 43" aria-hidden="true">
      <rect x="0" y="0" width="43" height="3.5" rx="1.75" fill={@ink} />
      <rect x="0" y="7.5" width="43" height="3.5" rx="1.75" fill={@ink} />
      <rect x="0" y="15" width="43" height="3.5" rx="1.75" fill={@ink} />
      <rect x="0" y="22.5" width="26" height="3.5" rx="1.75" fill={@ink} />
      <rect x="0" y="30" width="13" height="13" rx="2.5" fill={@ink} />
      <rect x="15" y="30" width="13" height="13" rx="2.5" fill={@ink} />
      <rect x="30" y="30" width="13" height="13" rx="2.5" fill="var(--tt-accentsoft)" />
    </svg>
    """
  end

  @doc "The name the site goes by. It names the browser tab and the wordmark."
  defdelegate site_title, to: Texttile.Settings

  @doc """
  The sections of the wordmark menu, in the order they stand there, and
  the digit each one answers to from anywhere in the admin area.

  One list, two readers: the menu draws itself from it, each row with
  its digit, and the bar's row of sections takes its screens from it,
  so the two can never drift apart.
  """
  def sections do
    [
      %{key: "1", label: gettext("New entry"), kind: :new},
      %{
        key: "2",
        label: gettext("Entries"),
        kind: :screen,
        to: ~p"/admin/texts",
        active: "texts"
      },
      %{
        key: "3",
        label: gettext("Comments"),
        kind: :screen,
        to: ~p"/admin/comments",
        active: "comments"
      },
      %{
        key: "4",
        label: gettext("Tags"),
        kind: :screen,
        to: ~p"/admin/tags",
        active: "tags"
      },
      %{
        key: "7",
        label: gettext("Newsletter"),
        kind: :screen,
        to: ~p"/admin/newsletter",
        active: "newsletter"
      },
      %{key: "8", label: gettext("Stats"), kind: :screen, to: ~p"/admin/stats", active: "stats"},
      %{
        key: "9",
        label: gettext("Settings"),
        kind: :screen,
        to: ~p"/admin/settings",
        active: "settings"
      },
      %{key: "0", label: gettext("View site"), kind: :site, to: ~p"/"}
    ]
  end

  @doc """
  The favicon of every page: the uploaded one from Settings, or the
  bundled Texttile mark. Uploaded names carry a random tag, so the
  browser cache never shows a stale icon.

  Beside it stands the square a phone puts on its home screen. A phone
  takes no SVG there, so that one is a PNG the site renders from the
  same picture, see `TexttileWeb.IconController`.
  """
  def favicon_link(assigns) do
    assigns =
      assign(
        assigns,
        :favicon,
        case Texttile.Settings.get(:favicon) do
          nil ->
            {~p"/images/texttile-mark.svg", "image/svg+xml"}

          stored ->
            {Texttile.Images.url(stored, :original),
             if(String.ends_with?(stored, ".png"), do: "image/png", else: "image/svg+xml")}
        end
      )

    ~H"""
    <link rel="icon" href={elem(@favicon, 0)} type={elem(@favicon, 1)} />
    <link rel="apple-touch-icon" href={~p"/apple-touch-icon.png"} />
    """
  end

  @doc """
  The column the sign-in family shares: the blog's own logo (or the
  Texttile mark) and its name, one quiet subtitle, then whatever the
  screen has to say.
  """
  attr :subtitle, :string, required: true
  slot :inner_block, required: true

  def auth(assigns) do
    assigns = assign(assigns, :brand, %{title: site_title(), logo: Texttile.Settings.get(:logo)})

    ~H"""
    <main class="auth-main min-h-[100dvh] flex items-start md:items-center justify-center px-4 pt-[7vh] md:pt-0 pb-10 md:pb-[10vh]">
      <div class="w-[min(374px,100%)]">
        <div class="flex items-center gap-[10px]">
          <img
            :if={@brand.logo}
            src={Texttile.Images.url(@brand.logo, :original)}
            alt=""
            class="h-[24px] w-auto max-w-[104px] object-contain"
          />
          <.mark :if={!@brand.logo} size={24} ink="var(--tt-ink)" />
          <span class="font-serif text-[18px] font-bold tracking-[-.015em] text-ink">
            {@brand.title}
          </span>
        </div>
        <h1 class="font-serif text-[28px] font-bold tracking-[-.02em] text-ink mt-6 leading-[1.15]">
          {@subtitle}
        </h1>
        {render_slot(@inner_block)}
        <%!-- the way back for whoever came here from the blog --%>
        <p class="mt-6 pt-4 border-t border-hair text-[13.5px]">
          <a class="link" href={~p"/"} id="back-to-blog">
            ← {gettext("Back to %{site}", site: @brand.title)}
          </a>
        </p>
      </div>
    </main>
    """
  end

  @doc """
  The admin area. The bar reads left to right: the wordmark, which is
  the section dropdown, the presence hint and the root of the breadcrumb;
  then the breadcrumb. No chips: everybody who is here is named in the
  dropdown. The bar does not scroll and does not clip: the menu under
  it is positioned fixed and placed by JS.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :crumb, :string, default: nil, doc: "what the breadcrumb says"
  attr :active, :string, default: nil, doc: "the section the crumb belongs to"
  attr :others, :list, default: [], doc: "presence: everybody here except the current user"

  attr :waiting, :integer,
    default: 0,
    doc: "comments that wait for a decision, counted beside Comments"

  attr :count, :any,
    default: nil,
    doc: "how many the screen lists: a phone, which names the screen in its bar, says it there"

  attr :wide, :boolean,
    default: false,
    doc: """
    the screen is about one thing, as the editor is about its entry: the
    bar names it in the crumb instead of showing the row of sections.
    Every bar stands on the same grid either way.
    """

  attr :bar_wide, :boolean,
    default: false,
    doc: "aligns a section-nav topbar to the two-column wide admin grid (e.g. Settings)"

  slot :lead,
    doc: """
    what stands beside the breadcrumb and belongs to it: the editor's
    state word. The left of the bar says what this screen is, the right
    says what you can do about it (round-15, variant A).
    """

  slot :bar,
    doc: "the right end of the bar: presence, the save state, the one control"

  slot :inner_block, required: true

  def app(assigns) do
    # The bar wears the site's own face: the uploaded logo (or the
    # Texttile mark) and the site title from Settings.
    assigns = assign(assigns, :brand, %{title: site_title(), logo: Texttile.Settings.get(:logo)})

    ~H"""
    <%!-- z-50: the blur makes the bar its own stacking layer, so the
         popovers inside it are bound to the bar's own place in the
         page. Below the formatting bar's 30 they would be painted
         over; above it they hang free, as a menu should. --%>
    <header
      id="topbar"
      class={[
        "sticky top-0 z-50 flex items-center gap-[6px] md:gap-2 h-[52px] border-b border-hair backdrop-blur-[8px] backdrop-saturate-150",
        "bar-col",
        (@wide || @bar_wide) && "wide"
      ]}
      role="banner"
    >
      <span class={["relative flex-none", @wide && "max-md:hidden"]}>
        <button
          class="flex items-center gap-[9px] text-[14.5px] font-[650] tracking-[-.02em] py-[5px] pl-[6px] pr-2 rounded-[5px] transition-colors hover:text-accent hover:bg-field aria-expanded:bg-field"
          id="wmBtn"
          type="button"
          aria-haspopup="true"
          aria-expanded="false"
          aria-controls="navMenu"
          aria-label={gettext("%{site}, sections menu", site: @brand.title)}
        >
          <span class="relative flex-none">
            <img
              :if={@brand.logo}
              src={Texttile.Images.url(@brand.logo, :original)}
              alt=""
              class="h-[21px] w-auto max-w-[84px] object-contain"
            />
            <.mark :if={!@brand.logo} size={21} />
            <span class="wmdot" id="wmDot" hidden={@others == []}></span>
          </span>
          <%!-- Desktop shows the blog's own name beside its mark; mobile shows
               the active section name + chevron so navigation is unmistakable
               and never looks like a site switcher. --%>
          <span
            :if={!@wide}
            class="hidden md:inline font-serif text-[15.5px] font-bold tracking-[-.015em] text-ink truncate max-w-[148px] -ml-[1px] leading-none relative top-[0.5px]"
          >
            {@brand.title}
          </span>
          <span
            :if={!@wide}
            class="md:hidden text-[14px] font-medium text-ink truncate max-w-[140px] -ml-[1px]"
          >
            {@crumb || gettext("Menu")}
          </span>
          <%!-- Mobile keeps the dropdown chevron beside the blog name; desktop
               uses the clean mark + name without a competing chevron next to <- Entries. --%>
          <span
            class={["text-dim -ml-[3px] mt-px", "md:hidden"]}
            aria-hidden="true"
          >
            <.chevron />
          </span>
          <span class="sr" id="wmSr">{here_now_sr(@others)}</span>
        </button>
      </span>
      <nav
        class="pop min-w-[248px] max-w-[340px]"
        id="navMenu"
        hidden
        aria-label={gettext("Sections")}
      >
        <%= for section <- sections() do %>
          <button
            :if={section.kind == :new}
            class="row"
            type="button"
            phx-click="new_text"
            data-key={section.key}
          >
            {section.label} <span class="k">{section.key}</span>
          </button>
          <.link
            :if={section.kind == :screen}
            navigate={section.to}
            class={["row", @active == section.active && "on"]}
            data-key={section.key}
          >
            {section.label} <span class="k">{section.key}</span>
          </.link>
          <%!-- the site opens beside the admin area: the writer keeps
               the entry they were working on --%>
          <a
            :if={section.kind == :site}
            class="row"
            href={section.to}
            target="_blank"
            rel="noopener"
            data-key={section.key}
          >
            {section.label} <span class="k">{section.key}</span>
          </a>
        <% end %>
        <div class="h-px bg-hair mx-0.5 my-[6px]"></div>
        <%!-- who is here: one block per person, every open tab a jump --%>
        <div id="liveBlock">
          <p class="px-[10px] pt-[3px] pb-[2px] text-[12.5px] text-faint leading-[1.45]">
            {gettext("Here now")}
          </p>
          <%= for person <- @others do %>
            <div class="who text-julia"><span class="dot live"></span>{person.name}</div>
            <.link :for={session <- person.sessions} navigate={session.path} class="row sub">
              <span class="flex-1 min-w-0 truncate">{session.label}</span>
              <span class="go">{gettext("go")}</span>
            </.link>
          <% end %>
          <p :if={@others == []} class="px-[10px] pb-[4px] text-[12.5px] text-faint">
            {gettext("No one else right now.")}
          </p>
        </div>
        <div class="h-px bg-hair mx-0.5 my-[6px]"></div>
        <p class="px-[10px] pt-[3px] pb-[2px] text-[12.5px] text-faint leading-[1.45]" id="wmMe">
          {@current_scope && Texttile.Accounts.display_name(@current_scope.user)}
        </p>
        <.link navigate={~p"/admin/profile"} class={["row", @active == "profile" && "on"]}>
          {gettext("Your profile")}
        </.link>
        <.link href={~p"/logout"} method="delete" class="row">{gettext("Sign out")}</.link>
        <%!-- which build runs, in every menu and nowhere a reader gets --%>
        <p class="px-[10px] pt-[6px] pb-[2px] text-[12.5px] text-faint tabular-nums" id="wmVersion">
          Texttile {Texttile.version()}
        </p>
      </nav>

      <%!-- Two zones. This is the left one: where you are. On a column
           screen it is the row of sections, the open one marked, and the
           open one is the crumb as well; a phone keeps only that one. A
           screen that is no section (the profile, the import) adds its
           own name. The editor, whose crumb is the entry, keeps the
           crumb alone, and whatever it puts in :lead stands beside it. --%>
      <%!-- on a phone, whatever the states say gives way before the
           buttons at the right and never runs under them. Only there:
           on a wide bar the clip would cut the focus ring of the
           sections, and the room is there anyway. --%>
      <span class={[
        "bar-lead flex items-center gap-[6px] md:gap-2 min-w-0 max-md:overflow-hidden text-[13.5px] text-dim",
        @wide && "ed-lead"
      ]}>
        <%= if @wide do %>
          <.link
            navigate={~p"/admin/texts"}
            class="inline-flex items-center gap-1 text-[13.5px] text-dim hover:text-ink transition-colors whitespace-nowrap"
            id="barBack"
          >
            &larr; {gettext("Entries")}
          </.link>
          {render_slot(@lead)}
        <% else %>
          <nav class={["barnav", !crumb_in_nav?(@crumb, @active) && "has-extra"]}>
            <.link
              :for={section <- screens()}
              navigate={section.to}
              id={crumb_in_nav?(@crumb, @active) && @active == section.active && "crumb"}
              class={["bn", @active == section.active && "on"]}
              aria-current={@active == section.active && "page"}
            >
              {section.label}<span
                :if={section.active == "comments" && @waiting > 0}
                class="bn-n num"
                id="navWaiting"
              ><span aria-hidden="true">{@waiting}</span><span class="sr">{ngettext(
                "1 comment waits",
                "%{count} comments wait",
                @waiting
              )}</span></span>
            </.link>
          </nav>
          {render_slot(@lead)}
        <% end %>
      </span>
      <%!-- the gap between the zones, and the only thing in the bar
           that gives way --%>
      <span class="flex-1 min-w-[6px]" aria-hidden="true"></span>
      <%!-- Quiet unboxed waiting-comments shortcut on mobile (hidden on Comments
           itself so the bar never points twice at the current screen) --%>
      <.link
        :if={!@wide && @waiting > 0 && @active != "comments"}
        navigate={~p"/admin/comments?status=waiting"}
        class="md:hidden inline-flex items-center self-stretch gap-1 text-[13px] text-dim hover:text-ink px-1.5 whitespace-nowrap"
        id="barWaiting"
        title={ngettext("1 comment waits", "%{count} comments wait", @waiting)}
      >
        <.speech_mark />
        <span class="num" aria-hidden="true">{@waiting}</span>
        <span class="sr">
          {ngettext("1 comment waits", "%{count} comments wait", @waiting)}
        </span>
      </.link>
      <%!-- who is signed in, on a desk: the way to the profile and the
           sign-out, in words instead of a chevron alone --%>
      <.link
        :if={!@wide && @current_scope}
        navigate={~p"/admin/profile"}
        id="barMe"
        class={["bar-me hidden md:inline-flex", @active == "profile" && "on"]}
        aria-current={@active == "profile" && "page"}
      >
        <%!-- a person, drawn: a name alone read as one more word of
             the bar and not as the account it is --%>
        <svg
          width="15"
          height="15"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          aria-hidden="true"
          class="mr-[7px] opacity-80"
        >
          <circle cx="12" cy="8" r="4" />
          <path d="M4.5 20.5c1.2-3.6 4.1-5.5 7.5-5.5s6.3 1.9 7.5 5.5" />
        </svg>
        {Texttile.Accounts.display_name(@current_scope.user)}
      </.link>
      {render_slot(@bar)}
    </header>

    <main>
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

  # The sections the bar shows as a row: the screens of the menu.
  defp screens, do: Enum.filter(sections(), &(&1.kind == :screen))

  # Whether the crumb is the name of the open section, so the marked
  # link of the row can carry it.
  defp crumb_in_nav?(crumb, active),
    do: Enum.any?(screens(), &(&1.active == active and &1.label == crumb))

  @doc """
  The door to the blog itself, at the end of the admin bar. Every screen
  of the admin area wears it; the editor is the exception, because there
  the way out leads to the one text on the screen and not to the front
  door.
  """
  def view_site(assigns) do
    ~H"""
    <a
      class="text-[12.5px] text-dim hover:text-accent whitespace-nowrap flex-none"
      id="bar-view-site"
      href={~p"/"}
    >
      {gettext("View site")}
    </a>
    """
  end

  # A speech mark: new comments, wherever they are counted.
  def speech_mark(assigns) do
    ~H"""
    <svg
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      stroke-width="1.6"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M3 3.5h10a1 1 0 0 1 1 1v6a1 1 0 0 1-1 1H7l-3 2.5v-2.5H3a1 1 0 0 1-1-1v-6a1 1 0 0 1 1-1Z" />
    </svg>
    """
  end

  defp chevron(assigns) do
    ~H"""
    <svg
      width="15"
      height="15"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="2.5"
      stroke-linecap="round"
      stroke-linejoin="round"
    >
      <path d="m6 9 6 6 6-6" />
    </svg>
    """
  end

  defp here_now_sr([]), do: ""

  defp here_now_sr(others) do
    names = Enum.map(others, & &1.name)

    ngettext(", %{names} is here", ", %{names} are here", length(names), names: and_list(names))
  end

  defp and_list([name]), do: name

  defp and_list(names) do
    {last, rest} = List.pop_at(names, -1)
    gettext("%{names} and %{last}", names: Enum.join(rest, ", "), last: last)
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
