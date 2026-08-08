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
     |> assign(:page_title, "Newsletter")
     |> assign(:add_error, false)
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

  # An address the other desk removed a moment ago is simply gone; the
  # list reloads either way.
  def handle_event("remove", %{"id" => id}, socket) do
    Newsletter.remove(id)
    {:noreply, load(socket)}
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
      crumb="Newsletter"
      active="newsletter"
      others={@others}
    >
      <div class="max-w-[760px] mx-auto px-[14px] md:px-6 pt-[22px] md:pt-[30px] pb-[90px]">
        <h1 class="page-h">Newsletter</h1>
        <p class="lead" id="newsletterSub">{sub_line(@subscribers, @confirmed)}</p>

        <form id="subAdd" phx-submit="add" class="flex flex-wrap items-center gap-2 mt-[6px]">
          <input
            type="email"
            name="email"
            placeholder="Email"
            aria-label="Email"
            required
            class="flex-1 min-w-[200px] max-w-[290px]"
          />
          <button class="btn">Add</button>
          <span :if={@add_error} id="subAddError" class="text-[12.5px]" style="color:var(--tt-julia)">
            That does not look like an email address.
          </span>
        </form>

        <div id="subList" class="mt-[18px]">
          <p :if={@subscribers == []} class="note">
            Nobody is on the list yet. Every reader who subscribes on the site
            shows up here, and so does every address you add.
          </p>
          <div
            :for={subscriber <- @subscribers}
            id={"sub-#{subscriber.id}"}
            class="flex items-center gap-x-3 py-[9px] border-b border-hair"
          >
            <span class="flex-1 min-w-0 flex flex-wrap items-baseline gap-x-3 gap-y-[2px]">
              <span class="text-[13.5px] font-semibold truncate max-w-full">
                {subscriber.email}
              </span>
              <span :if={!Subscriber.confirmed?(subscriber)} class="wait">
                waits for their confirmation
              </span>
            </span>
            <span class="hidden sm:inline text-[12.5px] text-faint num flex-none">
              {since(subscriber)}
            </span>
            <button
              class="btn ghost flex-none"
              type="button"
              phx-click="remove"
              phx-value-id={subscriber.id}
            >
              Remove
            </button>
          </div>
        </div>

        <p class="note mt-[22px] max-w-[62ch]" id="newsletterRule">
          A reader who subscribes on the site confirms the address by mail
          first; until then it gets no text. An address you add here is
          confirmed at once: you vouch for it. When a text goes live with
          Email subscribers checked, it goes to every confirmed address.
          <span :if={@protected?}>
            This blog asks for its access word, and every one of those mails
            carries it, so this list is who can read the blog.
          </span>
        </p>
      </div>
    </Layouts.app>
    """
  end

  # The lead line: how many addresses get the texts, and who still waits.
  defp sub_line([], _confirmed) do
    "Everybody who gets a mail when a new text goes live."
  end

  defp sub_line(subscribers, confirmed) do
    waiting = length(subscribers) - confirmed

    "#{confirmed} #{plural(confirmed, "address gets", "addresses get")} the texts by mail." <>
      if waiting == 0 do
        ""
      else
        " #{waiting} more #{plural(waiting, "waits", "wait")} for their confirmation."
      end
  end

  defp since(subscriber) do
    date = DateTime.to_date(subscriber.inserted_at)
    "#{date.day} #{Calendar.strftime(date, "%B %Y")}"
  end
end
