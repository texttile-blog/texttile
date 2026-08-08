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

  One list, two readers: the menu draws itself from it, and the key hint
  under the entries grid names the same digits, so the two can never
  drift apart.
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
            {"/uploads/" <> stored,
             if(String.ends_with?(stored, ".png"), do: "image/png", else: "image/svg+xml")}
        end
      )

    ~H"""
    <link rel="icon" href={elem(@favicon, 0)} type={elem(@favicon, 1)} />
    """
  end

  @doc """
  The column the sign-in family shares: the mark, the name, one quiet
  subtitle, then whatever the screen has to say.
  """
  attr :subtitle, :string, required: true
  slot :inner_block, required: true

  def auth(assigns) do
    ~H"""
    <main class="min-h-[100dvh] flex items-start justify-center px-5 pt-[13vh] pb-10">
      <div class="w-[min(374px,100%)]">
        <div class="flex items-center gap-[11px]">
          <.mark size={28} ink="var(--tt-ink)" />
          <h1 class="font-serif text-[26px] font-semibold tracking-[-.02em]">Texttile</h1>
        </div>
        <p class="text-faint text-[13px] mt-[6px]">{@subtitle}</p>
        {render_slot(@inner_block)}
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

  slot :bar,
    doc: "the right end of the bar, like the editor's in round-13: the Last-saved line"

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
      class="sticky top-0 z-50 flex items-center gap-[6px] md:gap-2 h-[52px] px-[10px] md:px-4 border-b border-rule backdrop-blur-[8px] backdrop-saturate-150"
      style="background:var(--tt-bar)"
      role="banner"
    >
      <span class="relative flex-none">
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
              src={"/uploads/#{@brand.logo}"}
              alt=""
              class="h-[21px] w-auto max-w-[84px] object-contain"
            />
            <.mark :if={!@brand.logo} size={21} />
            <span class="wmdot" id="wmDot" hidden={@others == []}></span>
          </span>
          <span class="hidden sm:inline">{@brand.title}</span>
          <span class="text-dim -ml-[2px] mt-px" aria-hidden="true"><.chevron /></span>
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
          <p class="px-[10px] pt-[3px] pb-[2px] text-[11.5px] text-faint leading-[1.45]">
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
        <p class="px-[10px] pt-[3px] pb-[2px] text-[11.5px] text-faint leading-[1.45]" id="wmMe">
          {@current_scope && Texttile.Accounts.display_name(@current_scope.user)}
        </p>
        <.link navigate={~p"/admin/profile"} class={["row", @active == "profile" && "on"]}>
          {gettext("Your profile")}
        </.link>
        <.link href={~p"/logout"} method="delete" class="row">{gettext("Sign out")}</.link>
      </nav>

      <%!-- the crumb is the one flexible thing in the bar, so the open
           section stays readable on a phone --%>
      <span class="flex items-baseline gap-[6px] md:gap-2 flex-1 min-w-0 text-[13.5px] text-dim">
        <span class="hidden sm:inline flex-none" style="color:var(--tt-slash)" aria-hidden="true">
          /
        </span>
        <span
          class="font-serif text-[15px] md:text-[16px] font-semibold text-ink tracking-[-.01em] truncate max-w-[24ch] md:max-w-[46ch]"
          id="crumb"
          title={@crumb}
        >
          {@crumb}
        </span>
      </span>
      {render_slot(@bar)}
    </header>

    <main>
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
    """
  end

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
