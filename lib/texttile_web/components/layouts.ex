defmodule TexttileWeb.Layouts do
  @moduledoc """
  The two shells of the app: `app/1` is the desk (topbar with the
  wordmark menu), `auth/1` is the one column the sign-in family shares.
  The design comes from the round-13 prototype.
  """
  use TexttileWeb, :html

  embed_templates "layouts/*"

  @themes [
    %{id: "paper", label: "Paper", page: "#faf9f7", accent: "#44614e"},
    %{id: "iris", label: "Iris", page: "#faf9f7", accent: "#6d35de"},
    %{id: "elixir", label: "Elixir", page: "#faf8fd", accent: "#7a3ff2"},
    %{id: "signal", label: "Signal", page: "#f4f3ef", accent: "#d02700"},
    %{id: "darkroom", label: "Darkroom", page: "#16181a", accent: "#e2a65c"}
  ]

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
  The desk. The bar reads left to right: the wordmark, which is the
  section dropdown, the presence hint and the root of the breadcrumb;
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

  slot :inner_block, required: true

  def app(assigns) do
    assigns = assign(assigns, :themes, @themes)

    ~H"""
    <header
      id="topbar"
      class="sticky top-0 z-30 flex items-center gap-[6px] md:gap-2 h-[52px] px-[10px] md:px-4 border-b border-rule backdrop-blur-[8px] backdrop-saturate-150"
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
          aria-label="Texttile, sections menu"
        >
          <span class="relative flex-none">
            <.mark size={21} />
            <span class="wmdot" id="wmDot" hidden={@others == []}></span>
          </span>
          <span class="hidden sm:inline">Texttile</span>
          <span class="text-dim -ml-[2px] mt-px" aria-hidden="true"><.chevron /></span>
          <span class="sr" id="wmSr">{here_now_sr(@others)}</span>
        </button>
      </span>
      <nav class="pop min-w-[248px] max-w-[340px]" id="navMenu" hidden aria-label="Sections">
        <button class="row" type="button">New text <span class="k">1</span></button>
        <.link navigate={~p"/"} class={["row", @active == "texts" && "on"]}>
          Texts <span class="k">2</span>
        </.link>
        <button class="row" type="button">Comments <span class="k">3</span></button>
        <button class="row" type="button">Newsletter <span class="k">7</span></button>
        <button class="row" type="button">Stats <span class="k">8</span></button>
        <button class="row" type="button">Settings <span class="k">9</span></button>
        <button class="row" type="button">View site <span class="k">0</span></button>
        <div class="h-px bg-hair mx-0.5 my-[6px]"></div>
        <%!-- who is here: one block per person, every open tab a jump --%>
        <div id="liveBlock">
          <p class="px-[10px] pt-[3px] pb-[2px] text-[11.5px] text-faint leading-[1.45]">
            Here now
          </p>
          <%= for person <- @others do %>
            <div class="who text-julia"><span class="dot live"></span>{person.name}</div>
            <.link :for={session <- person.sessions} navigate={session.path} class="row sub">
              <span class="flex-1 min-w-0 truncate">{session.label}</span>
              <span class="go">go</span>
            </.link>
          <% end %>
          <p :if={@others == []} class="px-[10px] pb-[4px] text-[12.5px] text-faint">
            No one else right now.
          </p>
        </div>
        <div class="h-px bg-hair mx-0.5 my-[6px]"></div>
        <p class="px-[10px] pt-[3px] pb-[2px] text-[11.5px] text-faint leading-[1.45]" id="wmMe">
          {@current_scope && Texttile.Accounts.display_name(@current_scope.user)}
        </p>
        <.link navigate={~p"/profile"} class={["row", @active == "profile" && "on"]}>
          Your profile
        </.link>
        <.link href={~p"/logout"} method="delete" class="row">Sign out</.link>
        <div class="h-px bg-hair mx-0.5 my-[6px]"></div>
        <%!-- the look of the desk: five themes, one row of swatches --%>
        <p class="px-[10px] pt-[3px] pb-[2px] text-[11.5px] text-faint leading-[1.45]">Theme</p>
        <div
          class="grid grid-cols-5 gap-[2px] px-[6px] pb-[3px]"
          id="themeRow"
          role="group"
          aria-label="Theme"
        >
          <button
            :for={theme <- @themes}
            type="button"
            class="swatch"
            data-t={theme.id}
            aria-pressed="false"
            title={theme.label}
          >
            <i style={"background:linear-gradient(135deg, #{theme.page} 0 52%, #{theme.accent} 52%)"}></i>{theme.label}
          </button>
        </div>
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
    </header>

    <main>
      {render_slot(@inner_block)}
    </main>

    <.flash_group flash={@flash} />
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
    verb = if length(names) == 1, do: "is here", else: "are here"
    ", " <> and_list(names) <> " " <> verb
  end

  defp and_list([name]), do: name

  defp and_list(names) do
    {last, rest} = List.pop_at(names, -1)
    Enum.join(rest, ", ") <> " and " <> last
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
