defmodule TexttileWeb.ProfileLive do
  @moduledoc """
  Your profile: your name, your address, your password, your open
  sessions. Nothing here has a Save button: every change applies the
  moment you make it, and the Last-saved line in the corner keeps
  itself current.
  """
  use TexttileWeb, :live_view

  alias Texttile.Accounts
  alias Texttile.Accounts.Scope
  alias TexttileWeb.Desk

  @note_ms 4600

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    socket =
      socket
      |> assign(:page_title, "Your profile")
      |> assign(:sessions, Accounts.list_sessions(scope.user))
      |> assign(:pw_note, nil)
      |> assign_forms(scope.user)
      |> mark_saved(nil)

    {:ok, socket}
  end

  def handle_event("save_profile", %{"_target" => target, "user" => params}, socket) do
    user = socket.assigns.current_scope.user

    result =
      case target do
        ["user", "display_name"] -> Accounts.update_display_name(user, params["display_name"])
        ["user", "username"] -> Accounts.update_username(user, params["username"])
        ["user", "email"] -> Accounts.update_email(user, params["email"])
        _ -> {:ok, user}
      end

    case result do
      {:ok, user} ->
        scope = Scope.for_user(user, socket.assigns.current_scope.session_token)
        Desk.rename(scope, Accounts.display_name(user))

        {:noreply,
         socket
         |> assign(:current_scope, scope)
         |> assign_forms(user, params)
         |> mark_saved(nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_form, to_form(changeset, action: :validate))}
    end
  end

  def handle_event("set_password", %{"pw" => pw_params}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_password(user, pw_params["current_password"], pw_params["password"]) do
      {:ok, user} ->
        scope = Scope.for_user(user, socket.assigns.current_scope.session_token)

        {:noreply,
         socket
         |> assign(:current_scope, scope)
         |> assign(:pw_form, to_form(%{}, as: :pw))
         |> assign(
           :pw_note,
           "Your new password is set. Nothing was mailed to anyone: you changed your own."
         )
         |> mark_saved("Password changed · just now")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:pw_note, nil)
         |> assign(:pw_form, to_form(changeset, as: :pw, action: :validate))}
    end
  end

  defp assign_forms(socket, user, merge \\ %{}) do
    values = %{
      "display_name" => user.display_name,
      "username" => user.username,
      "email" => user.email
    }

    socket
    |> assign(
      :profile_form,
      to_form(Map.merge(values, Map.take(merge, Map.keys(values))), as: :user)
    )
    |> assign_new(:pw_form, fn -> to_form(%{}, as: :pw) end)
  end

  defp mark_saved(socket, note) do
    now = System.system_time(:millisecond)

    socket
    |> assign(:saved_at, now)
    |> assign(:saved_note, note)
    |> assign(:saved_note_until, if(note, do: now + @note_ms))
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      crumb="Your profile"
      active="profile"
      others={@others}
    >
      <div class="quiet-fields max-w-[760px] mx-auto px-[14px] md:px-6 pt-[22px] md:pt-[30px] pb-[90px]">
        <div class="flex items-baseline gap-[14px] flex-wrap">
          <h1 class="page-h">Your profile</h1>
          <span class="sp"></span>
          <span
            class="text-[12.5px] text-faint num whitespace-nowrap"
            id="savedProfile"
            phx-hook=".SavedTicker"
            data-at={@saved_at}
            data-note={@saved_note}
            data-note-until={@saved_note_until}
          >
            Last saved · just now
          </span>
        </div>
        <p class="lead">
          You are signed in as <b id="profileWho">{Accounts.display_name(@current_scope.user)}</b>.
          This screen is yours alone: your name, your address, your password,
          your open sessions. Nothing here has a Save button: every change
          applies the moment you make it.
        </p>

        <h2 class="text-[15px] font-semibold text-ink tracking-[-.01em] mt-9 mb-[13px] pb-2 border-b border-rule">
          You
        </h2>
        <.form for={@profile_form} id="profile-form" phx-change="save_profile">
          <div class="drow">
            <label class="lab" for={@profile_form[:display_name].id}>Displayed name</label>
            <span class="val">
              <input
                type="text"
                id={@profile_form[:display_name].id}
                name={@profile_form[:display_name].name}
                value={@profile_form[:display_name].value}
                phx-debounce="300"
              />
              <div class="hint">
                What the others see, and it changes everywhere the moment you
                type it: the Texttile menu, the log of every text from here on.
                Empty falls back to the username.
              </div>
            </span>
          </div>
          <div class="drow">
            <label class="lab" for={@profile_form[:username].id}>Username</label>
            <span class="val">
              <input
                type="text"
                id={@profile_form[:username].id}
                name={@profile_form[:username].name}
                value={@profile_form[:username].value}
                spellcheck="false"
                autocapitalize="off"
                autocorrect="off"
                phx-debounce="500"
              />
              <.field_errors field={@profile_form[:username]} />
              <div class="hint">
                The name you sign in with. It must be unique: no two accounts
                carry the same one. Lower case letters, digits, dot, dash and
                underscore.
              </div>
            </span>
          </div>
          <div class="drow">
            <label class="lab" for={@profile_form[:email].id}>Email</label>
            <span class="val">
              <input
                type="email"
                id={@profile_form[:email].id}
                name={@profile_form[:email].name}
                value={@profile_form[:email].value}
                phx-debounce="500"
              />
              <.field_errors field={@profile_form[:email]} />
              <div class="hint">
                Where notifications and password links go. You never sign in
                with it. Readers never see it.
              </div>
            </span>
          </div>
        </.form>

        <h2 class="text-[15px] font-semibold text-ink tracking-[-.01em] mt-9 mb-[13px] pb-2 border-b border-rule">
          Password
        </h2>
        <.form for={@pw_form} id="password-form" phx-submit="set_password">
          <div class="drow">
            <span class="lab">New password</span>
            <span class="val">
              <span class="flex items-end gap-[10px] flex-wrap">
                <span class="flex-1 min-w-[180px] max-w-[260px]">
                  <label class="block text-[12px] text-dim mb-[3px]" for="pw-current">
                    Current password
                  </label>
                  <input
                    type="password"
                    id="pw-current"
                    name="pw[current_password]"
                    autocomplete="current-password"
                  />
                </span>
                <span class="flex-1 min-w-[180px] max-w-[260px]">
                  <label class="block text-[12px] text-dim mb-[3px]" for="pw-new">
                    New password
                  </label>
                  <input
                    type="password"
                    id="pw-new"
                    name="pw[password]"
                    autocomplete="new-password"
                  />
                </span>
                <button class="btn" type="submit">Set</button>
              </span>
              <.field_errors field={@pw_form[:current_password]} />
              <.field_errors field={@pw_form[:password]} />
              <div class="hint">
                Your own, and only yours: confirm the current password once and
                the new one takes over, at least 12 characters. This is the only
                password field in the app, because nobody ever sets anybody
                else's.
              </div>
              <p :if={@pw_note} class="note mt-[7px]" id="pwMeState">{@pw_note}</p>
            </span>
          </div>
        </.form>

        <h2 class="text-[15px] font-semibold text-ink tracking-[-.01em] mt-9 mb-[13px] pb-2 border-b border-rule">
          Your sessions
        </h2>
        <div id="sessions">
          <div
            :for={session <- @sessions}
            class="flex items-center gap-3 py-[13px] border-b border-hair text-[13.5px]"
          >
            <span class="flex-1 min-w-0">
              {session_label(session, @current_scope)} · signed in {signed_in_on(session)}
            </span>
            <span :if={length(@sessions) == 1} class="note">the only one open</span>
          </div>
        </div>
        <p class="note mt-3">Signing out ends this session only.</p>
        <p class="mt-4">
          <.link href={~p"/logout"} method="delete" class="btn" id="sign-out">Sign out</.link>
        </p>
      </div>
    </Layouts.app>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".SavedTicker">
      export default {
        mounted() {
          this.timer = setInterval(() => this.paint(), 1000)
          this.paint()
        },
        updated() { this.paint() },
        destroyed() { clearInterval(this.timer) },
        paint() {
          const now = Date.now()
          const note = this.el.dataset.note
          const until = Number(this.el.dataset.noteUntil || 0)
          if (note && now < until) { this.el.textContent = note; return }
          const at = Number(this.el.dataset.at || now)
          const d = new Date(at)
          const pad = n => String(n).padStart(2, "0")
          this.el.textContent = (now - at) / 1000 < 20
            ? "Last saved · just now"
            : `Last saved ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
        }
      }
    </script>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true

  defp field_errors(assigns) do
    # A form only carries errors after a refused update, so every error
    # in it is worth showing.
    assigns = assign(assigns, :errors, Enum.map(assigns.field.errors, &translate_error/1))

    ~H"""
    <p :for={message <- @errors} class="text-julia text-[13px] mt-[6px]">{message}</p>
    """
  end

  defp session_label(session, scope) do
    if session.token == scope.session_token, do: "This browser", else: "Another browser"
  end

  defp signed_in_on(session) do
    date = DateTime.to_date(session.inserted_at)

    case Date.diff(Date.utc_today(), date) do
      0 -> "today"
      1 -> "yesterday"
      _ -> Date.to_string(date)
    end
  end
end
