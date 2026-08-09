defmodule TexttileWeb.CoreComponents do
  @moduledoc """
  The components more than one screen uses.

  Each one is here because a second screen asked for it. A component that
  only one screen draws stays in that screen, where you can read it next
  to the markup around it.

  Styling is Tailwind CSS with the tokens in `assets/css/app.css`. The
  screens draw their own forms and buttons, so there is no generic input
  or table here.

    * [Heroicons](https://heroicons.com), see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html),
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: TexttileWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="fixed left-4 bottom-4 z-[95] flex items-start gap-3 bg-paper px-4 py-3 text-[13px] max-w-[min(420px,calc(100vw-32px))]"
      style="border-radius: var(--tt-radius-pop); border: 1px solid var(--tt-rule); box-shadow: 0 14px 34px rgb(var(--tt-shadow) / .2)"
      {@rest}
    >
      <span :if={@kind == :error} class="dot text-julia mt-[6px]" aria-hidden="true"></span>
      <div class="min-w-0">
        <p :if={@title} class="font-semibold">{@title}</p>
        <p class={[@kind == :error && "text-julia"]}>{msg}</p>
      </div>
      <button type="button" class="note hover:text-ink cursor-pointer" aria-label={gettext("close")}>
        ✕
      </button>
    </div>
    """
  end

  @doc """
  The one question the admin area asks before a step it cannot take back, or
  before one that reaches other people: a scrim, a heading, what is
  about to happen, and the two answers. Escape and the scrim itself
  both mean Cancel, so nothing here is a trap.

  `value` travels back with the confirming click as `phx-value-id`, for
  a screen whose question is about one row of many.

  ## Examples

      <.ask
        :if={@confirm_delete}
        heading="Delete this comment?"
        ok="Delete"
        on_ok="confirm_delete_comment"
        value={@confirm_delete.id}
      >
        <p>It leaves the text at once.</p>
      </.ask>
  """
  attr :heading, :string, required: true
  attr :ok, :string, required: true
  attr :on_ok, :string, required: true
  attr :on_cancel, :string, default: "cancel_dialog"
  attr :value, :any, default: nil
  slot :inner_block, required: true

  def ask(assigns) do
    ~H"""
    <div
      id="scrim"
      class="fixed inset-0 z-[80] grid place-items-center p-5"
      style="background: var(--tt-scrim)"
      phx-click={@on_cancel}
      phx-window-keydown={@on_cancel}
      phx-key="escape"
    >
      <div
        class="w-[min(430px,100%)] bg-paper px-[22px] pt-5 pb-[18px]"
        style="border-radius: var(--tt-radius-pop); border: 1px solid var(--tt-rule); box-shadow: 0 22px 54px rgb(var(--tt-shadow) / .26)"
        role="dialog"
        aria-modal="true"
        aria-labelledby="dlgH"
        id="dialog"
        phx-click-away={@on_cancel}
      >
        <h2 class="font-serif text-[19px] font-semibold tracking-[-.01em]" id="dlgH">
          {@heading}
        </h2>
        <div class="text-[13.5px] text-inksoft mt-[9px] leading-[1.55]">
          {render_slot(@inner_block)}
        </div>
        <div class="flex gap-2 mt-[18px]">
          <button class="btn solid" id="dialog-ok" phx-click={@on_ok} phx-value-id={@value} autofocus>
            {@ok}
          </button>
          <button class="btn quiet" id="dialog-cancel" phx-click={@on_cancel}>
            {gettext("Cancel")}
          </button>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  @doc """
  The formatting bar over a Markdown surface: quiet buttons for the
  admin who does not know Markdown, and nothing in the way of the one
  who does. Every button writes plain Markdown through the same
  commands the keyboard uses; the editor hook swallows the mousedown so
  the caret never leaves the text, and finds this bar by its id.

  `files: false` takes the image button off, for a surface that holds
  words and no pictures.
  """
  attr :id, :string, required: true
  attr :files, :boolean, default: true
  attr :readonly, :boolean, default: false
  attr :note, :string, default: nil
  attr :class, :any, default: nil

  def md_bar(assigns) do
    ~H"""
    <div
      class={["mdbar", @readonly && "is-readonly", @class]}
      id={@id}
      role="toolbar"
      aria-label={gettext("Formatting")}
    >
      <button
        type="button"
        class="mdb"
        data-cmd="heading"
        title={gettext("Heading. Click again for the next size.")}
        aria-label={gettext("Heading")}
      >
        <span class="g font-serif font-semibold text-[15px]">H</span>
      </button>
      <button
        type="button"
        class="mdb"
        data-cmd="bold"
        title={gettext("Bold (Ctrl or Cmd + B)")}
        aria-label={gettext("Bold")}
      >
        <span class="g font-serif font-bold text-[14.5px]">B</span>
      </button>
      <button
        type="button"
        class="mdb"
        data-cmd="italic"
        title={gettext("Italic (Ctrl or Cmd + I)")}
        aria-label={gettext("Italic")}
      >
        <span class="g font-serif italic font-semibold text-[14.5px]">I</span>
      </button>
      <button
        type="button"
        class="mdb"
        data-cmd="link"
        title={gettext("Link (Ctrl or Cmd + K)")}
        aria-label={gettext("Link")}
      >
        <svg
          class="g"
          viewBox="0 0 16 16"
          fill="none"
          stroke="currentColor"
          stroke-width="1.6"
          stroke-linecap="round"
        >
          <path d="M6.5 9.5 9.5 6.5" />
          <path d="M7.2 4.6l1.5-1.5a2.6 2.6 0 0 1 3.7 3.7l-1.5 1.5" />
          <path d="M8.8 11.4l-1.5 1.5a2.6 2.6 0 0 1-3.7-3.7l1.5-1.5" />
        </svg>
      </button>
      <span class="mdsep" aria-hidden="true"></span>
      <button
        type="button"
        class="mdb"
        data-cmd="quote"
        title={gettext("Quote")}
        aria-label={gettext("Quote")}
      >
        <span class="g font-serif font-bold text-[17px] leading-none pt-[5px]">&rdquo;</span>
      </button>
      <button
        type="button"
        class="mdb"
        data-cmd="bullet"
        title={gettext("List")}
        aria-label={gettext("List")}
      >
        <svg
          class="g"
          viewBox="0 0 16 16"
          fill="none"
          stroke="currentColor"
          stroke-width="1.6"
          stroke-linecap="round"
        >
          <circle cx="3" cy="4" r=".4" fill="currentColor" />
          <circle cx="3" cy="8" r=".4" fill="currentColor" />
          <circle cx="3" cy="12" r=".4" fill="currentColor" />
          <path d="M6.5 4h6.5M6.5 8h6.5M6.5 12h6.5" />
        </svg>
      </button>
      <button
        type="button"
        class="mdb"
        data-cmd="ordered"
        title={gettext("Numbered list")}
        aria-label={gettext("Numbered list")}
      >
        <svg
          class="g"
          viewBox="0 0 16 16"
          fill="none"
          stroke="currentColor"
          stroke-width="1.6"
          stroke-linecap="round"
        >
          <path d="M7.5 4h5.5M7.5 8h5.5M7.5 12h5.5" />
          <text x="1.6" y="6" font-size="6.5" fill="currentColor" stroke="none" font-family="inherit">
            1
          </text>
          <text x="1.6" y="14" font-size="6.5" fill="currentColor" stroke="none" font-family="inherit">
            2
          </text>
        </svg>
      </button>
      <button
        type="button"
        class="mdb"
        data-cmd="task"
        title={gettext("Task list. Click a box in the text to tick it.")}
        aria-label={gettext("Task list")}
      >
        <svg
          class="g"
          viewBox="0 0 16 16"
          fill="none"
          stroke="currentColor"
          stroke-width="1.6"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <rect x="2.2" y="2.2" width="11.6" height="11.6" rx="2.6" />
          <path d="M5.2 8.2l2 2 3.6-4" />
        </svg>
      </button>
      <span class="mdsep" aria-hidden="true"></span>
      <button
        type="button"
        class="mdb"
        data-cmd="code"
        title={gettext("Code")}
        aria-label={gettext("Code")}
      >
        <svg
          class="g"
          viewBox="0 0 16 16"
          fill="none"
          stroke="currentColor"
          stroke-width="1.6"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <path d="M6 4.5 2.5 8 6 11.5" />
          <path d="M10 4.5 13.5 8 10 11.5" />
        </svg>
      </button>
      <button
        :if={@files}
        type="button"
        class="mdb"
        data-cmd="image"
        title={gettext("Put an image in the text, at the caret")}
        aria-label={gettext("Image")}
      >
        <svg
          class="g"
          viewBox="0 0 16 16"
          fill="none"
          stroke="currentColor"
          stroke-width="1.6"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <rect x="2.2" y="3.2" width="11.6" height="9.6" rx="1.6" />
          <circle cx="5.6" cy="6.4" r="1" />
          <path d="M2.6 11.4 6.5 8l3 2.6 1.9-1.6 2.2 2" />
        </svg>
      </button>
      <span class="sp"></span>
      <span :if={@note} class="note hidden sm:inline self-center">{@note}</span>
    </div>
    """
  end

  @doc """
  The format contract of the import, where anybody can read it: the
  file lives in the repository, so the link leaves the site.
  """
  def import_doc(assigns) do
    ~H"""
    <a
      class="link"
      id="import-doc"
      href="https://github.com/texttile-blog/texttile/blob/main/IMPORT.md"
      target="_blank"
      rel="noopener"
    >
      IMPORT.md<.out_icon />
    </a>
    """
  end

  @doc """
  The mark of a link that opens a tab of its own: an arrow leaving its
  box. It stands after the words, never instead of them, so it carries
  no label for a screen reader.
  """
  def out_icon(assigns) do
    ~H"""
    <svg
      class="out-i"
      viewBox="0 0 16 16"
      fill="none"
      stroke="currentColor"
      stroke-width="1.5"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <path d="M9.5 3h3.5v3.5" />
      <path d="M13 3 8.2 7.8" />
      <path d="M12 9.7V12a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V5a1 1 0 0 1 1-1h2.3" />
    </svg>
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates one error message.

  A changeset writes its messages while it runs, so the string arrives
  here as a value and not as a literal the extractor could read. The
  literals stand in `TexttileWeb.EctoMessages` instead, in the same
  domain as every other word of the site: one file per language holds
  all of them.
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.ngettext(TexttileWeb.Gettext, msg, msg, count, opts)
    else
      Gettext.gettext(TexttileWeb.Gettext, msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
