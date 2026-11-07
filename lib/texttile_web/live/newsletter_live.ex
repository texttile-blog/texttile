defmodule TexttileWeb.NewsletterLive do
  @moduledoc """
  The Newsletter overview: everybody on the list, newest first, each
  with the state of their address and a Remove. The form at the top
  adds an address by hand, confirmed at once - the admin vouches for
  it. The lead line carries the counts; the note at the foot carries
  the rule.
  """

  use TexttileWeb, :live_view

  alias Texttile.Newsletter
  alias Texttile.Newsletter.Subscriber
  alias Texttile.Settings

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Newsletter.subscribe()
      Settings.subscribe()
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Newsletter"))
     |> assign(:add_error, false)
     |> assign(:confirm_remove, nil)
     |> load()}
  end

  defp load(socket) do
    subscribers = Newsletter.list()

    socket
    |> assign(:subscribers, subscribers)
    |> assign(:confirmed, Enum.count(subscribers, &Subscriber.confirmed?/1))
    |> assign(:protected?, Settings.guarded?())
  end

  def handle_event("add", %{"email" => email}, socket) do
    case Newsletter.add(email) do
      {:ok, _subscriber} ->
        {:noreply, socket |> assign(:add_error, false) |> load()}

      {:error, :invalid} ->
        {:noreply, assign(socket, :add_error, true)}
    end
  end

  # Taking an address off cannot be undone: nobody can put a reader
  # back on the list on their behalf, and the reader is never told. So
  # it asks first, like every other step of that kind here.
  def handle_event("ask_remove", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.subscribers, &(to_string(&1.id) == to_string(id))) do
      nil -> {:noreply, load(socket)}
      subscriber -> {:noreply, assign(socket, :confirm_remove, subscriber)}
    end
  end

  def handle_event("cancel_remove", _params, socket) do
    {:noreply, assign(socket, :confirm_remove, nil)}
  end

  # An address another admin removed a moment ago is simply gone; the
  # list reloads either way.
  def handle_event("remove", _params, socket) do
    # nil on a double click: the first click already closed the dialog
    if subscriber = socket.assigns.confirm_remove, do: Newsletter.remove(subscriber.id)

    {:noreply, socket |> assign(:confirm_remove, nil) |> load()}
  end

  def handle_info({:newsletter_changed}, socket), do: {:noreply, load(socket)}

  def handle_info({:setting_changed, key, _value}, socket)
      when key in [:site_visibility, :site_password] do
    {:noreply, load(socket)}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      crumb={gettext("Newsletter")}
      count={@confirmed}
      active="newsletter"
      others={@others}
    >
      <:bar>
        <Layouts.view_site />
      </:bar>
      <div class="admin-col">
        <div class="mb-[9px] md:mb-6">
          <h1 class="page-h">{gettext("Newsletter")}</h1>
          <p class="lead !mb-0 num max-md:hidden" id="newsletterSub">
            {sub_line(@subscribers, @confirmed)}
          </p>
        </div>
        <div>
          <form id="subAdd" phx-submit="add" class="flex flex-wrap items-center gap-2">
            <input
              type="email"
              name="email"
              placeholder={gettext("Email")}
              aria-label={gettext("Email")}
              required
              class="flex-1 min-w-[200px]"
            />
            <button class="btn solid">{gettext("Add")}</button>
            <span
              :if={@add_error}
              id="subAddError"
              class="text-[12.5px]"
              style="color:var(--tt-julia)"
            >
              {gettext("That does not look like an email address.")}
            </span>
          </form>

          <div id="subList" class={["mt-7", @subscribers != [] && "border-t border-hair"]}>
            <p :if={@subscribers == []} class="note">
              {gettext(
                "Nobody is on the list yet. Every reader who subscribes on the site shows up here, and so does every address you add."
              )}
            </p>
            <div
              :for={subscriber <- @subscribers}
              id={"sub-#{subscriber.id}"}
              class="flex items-start sm:items-center gap-x-3 py-[9px] sm:py-[12px] border-b border-hair"
            >
              <span class="flex-1 min-w-0 flex flex-wrap items-baseline gap-x-3 gap-y-[2px]">
                <%!-- the address on a fixed column, its day beside it as
                     Tags sets a count beside a name; the right is for
                     the action alone --%>
                <span class="rowp truncate max-w-full sm:w-[260px] sm:flex-none">
                  {subscriber.email}
                </span>
                <span class="hidden sm:inline text-[13px] text-faint num">
                  {since(subscriber)}
                </span>
                <span :if={!Subscriber.confirmed?(subscriber)} class="wait">
                  {gettext("waits for their confirmation")}
                </span>
                <%!-- a phone says the day under the address: it knows
                     what the desk knows --%>
                <span class="sm:hidden basis-full text-[12.5px] text-faint num">
                  {since(subscriber)}
                </span>
              </span>
              <button
                class="btn quiet sm danger flex-none -mr-[11px] max-sm:-mt-[5px]"
                type="button"
                id={"remove-#{subscriber.id}"}
                phx-click="ask_remove"
                phx-value-id={subscriber.id}
              >
                {gettext("Remove")}
              </button>
            </div>
          </div>

          <p class="hint mt-[16px]" id="newsletterRule">
            {gettext("Readers confirm by mail first; an address added here is confirmed at once.")}
            <span :if={@protected?}>
              {gettext(
                "This blog asks for its access word, and every one of those mails carries it, so this list is who can read the blog."
              )}
            </span>
          </p>
        </div>
      </div>

      <.ask
        :if={@confirm_remove}
        heading={gettext("Take %{email} off the list?", email: @confirm_remove.email)}
        ok={gettext("Remove the address")}
        on_ok="remove"
        on_cancel="cancel_remove"
      >
        <p>
          <b>{@confirm_remove.email}</b>
          {gettext(
            "gets no mail from this blog from the moment you confirm, and the reader is not told."
          )}
          <br />
          <br />
          {gettext(
            "There is no undo, and nobody can put the address back on the list for them: a reader subscribes on the site, or you add the address here again and vouch for it yourself."
          )}
        </p>
      </.ask>
    </Layouts.app>
    """
  end

  # The count beside the heading: a short noun, the way every admin
  # list counts, and who still waits after it.
  defp sub_line(subscribers, confirmed) do
    waiting = length(subscribers) - confirmed
    line = ngettext("1 subscriber", "%{count} subscribers", confirmed)

    if waiting == 0 do
      line
    else
      line <> " · " <> ngettext("1 waiting", "%{count} waiting", waiting)
    end
  end

  defp since(subscriber) do
    day = subscriber.inserted_at |> DateTime.to_date() |> Texttile.I18n.format_short_date()
    gettext("since %{day}", day: day)
  end
end
