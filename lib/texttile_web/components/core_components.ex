defmodule TexttileWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
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
          <button class="btn quiet" id="dialog-cancel" phx-click={@on_cancel}>Cancel</button>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label for={@id}>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
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
      aria-label="Formatting"
    >
      <button
        type="button"
        class="mdb"
        data-cmd="heading"
        title="Heading. Click again for the next size."
        aria-label="Heading"
      >
        <span class="g font-serif font-semibold text-[15px]">H</span>
      </button>
      <button
        type="button"
        class="mdb"
        data-cmd="bold"
        title="Bold (Ctrl or Cmd + B)"
        aria-label="Bold"
      >
        <span class="g font-serif font-bold text-[14.5px]">B</span>
      </button>
      <button
        type="button"
        class="mdb"
        data-cmd="italic"
        title="Italic (Ctrl or Cmd + I)"
        aria-label="Italic"
      >
        <span class="g font-serif italic font-semibold text-[14.5px]">I</span>
      </button>
      <button
        type="button"
        class="mdb"
        data-cmd="link"
        title="Link (Ctrl or Cmd + K)"
        aria-label="Link"
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
      <button type="button" class="mdb" data-cmd="quote" title="Quote" aria-label="Quote">
        <span class="g font-serif font-bold text-[17px] leading-none pt-[5px]">&rdquo;</span>
      </button>
      <button type="button" class="mdb" data-cmd="bullet" title="List" aria-label="List">
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
        title="Numbered list"
        aria-label="Numbered list"
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
        title="Task list. Click a box in the text to tick it."
        aria-label="Task list"
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
      <button type="button" class="mdb" data-cmd="code" title="Code" aria-label="Code">
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
        title="Put an image in the text, at the caret"
        aria-label="Image"
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

  @doc """
  The word that goes with a count: the first for one, the second for
  everything else. The lead lines of the admin screens count things.
  """
  def plural(1, one, _many), do: one
  def plural(_n, _one, many), do: many
end
