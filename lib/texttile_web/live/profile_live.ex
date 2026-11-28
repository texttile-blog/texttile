defmodule TexttileWeb.ProfileLive do
  @moduledoc """
  Your profile: your name, your address, your password, your open
  sessions. The displayed name has no Save button; it applies the
  moment you type it, a toast answers it, and the Last-saved stamp in
  the bar keeps itself current. The address and the password are the two that ask
  for the password first, because each of them owns the account.
  """
  use TexttileWeb, :live_view

  alias Texttile.Accounts
  alias Texttile.Accounts.Scope
  alias TexttileWeb.Admin

  @note_ms 4600

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Texttile.PubSub, Accounts.sessions_topic(scope.user.id))
    end

    socket =
      socket
      |> assign(:page_title, gettext("Your profile"))
      |> assign(:sessions, Accounts.list_sessions(scope.user))
      |> assign(:pw_note, nil)
      |> assign(:email_note, nil)
      |> assign_forms(scope.user)
      |> assign(:saved_at, nil)
      |> assign(:saved_note, nil)
      |> assign(:saved_note_until, nil)

    {:ok, socket}
  end

  def handle_info(:sessions_changed, socket) do
    {:noreply,
     assign(socket, :sessions, Accounts.list_sessions(socket.assigns.current_scope.user))}
  end

  def handle_event("save_profile", %{"_target" => target, "user" => params}, socket) do
    user = socket.assigns.current_scope.user

    result =
      case target do
        ["user", "display_name"] -> Accounts.update_display_name(user, params["display_name"])
        _ -> {:ok, user}
      end

    case result do
      {:ok, user} ->
        scope = Scope.for_user(user, socket.assigns.current_scope.session_token)
        Admin.announce_rename(user.id)

        {:noreply,
         socket
         |> assign(:current_scope, scope)
         |> assign_forms(user)
         |> mark_saved(nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :profile_form, to_form(changeset, action: :validate))}
    end
  end

  # The address is the identity here, so moving it is not a field that
  # saves itself: it asks for the password first. A stolen session must
  # not be able to point the next password link at another inbox.
  # The password and the button belong to a change, so they appear the
  # moment the address differs from the saved one, and go again when it
  # is typed back.
  def handle_event("email_draft", %{"em" => %{"email" => email}}, socket) do
    saved = socket.assigns.current_scope.user.email

    {:noreply,
     socket
     |> assign(:email_form, to_form(%{"email" => email}, as: :em))
     |> assign(:email_moved, String.trim(email) != saved)}
  end

  def handle_event("set_email", %{"em" => em_params}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_email(user, em_params["email"], em_params["current_password"]) do
      {:ok, user} ->
        scope = Scope.for_user(user, socket.assigns.current_scope.session_token)
        Admin.announce_rename(user.id)

        {:noreply,
         socket
         |> assign(:current_scope, scope)
         |> assign_forms(user)
         |> assign(
           :email_note,
           gettext("Your account is at %{email} now. You sign in with it from now on.",
             email: user.email
           )
         )
         |> mark_saved(gettext("Address changed · just now"))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:email_note, nil)
         |> assign(:email_moved, true)
         |> assign(:email_form, to_form(changeset, as: :em, action: :validate))}
    end
  end

  def handle_event("set_password", %{"pw" => pw_params}, socket) do
    user = socket.assigns.current_scope.user

    case Accounts.update_password(user, pw_params["current_password"], pw_params["password"]) do
      {:ok, user} ->
        token = socket.assigns.current_scope.session_token
        scope = Scope.for_user(user, token)

        # a changed password ends every other session, and the browsers
        # behind them are told to disconnect right away
        user
        |> Accounts.list_sessions()
        |> Enum.reject(&(&1.token_hash == Accounts.session_fingerprint(token)))
        |> Enum.each(
          &TexttileWeb.Endpoint.broadcast(
            TexttileWeb.UserAuth.user_session_topic(&1.token_hash),
            "disconnect",
            %{}
          )
        )

        Accounts.delete_sessions_except(user, token)

        {:noreply,
         socket
         |> assign(:current_scope, scope)
         |> assign(:sessions, Accounts.list_sessions(user))
         |> assign(:pw_form, to_form(%{}, as: :pw))
         |> assign(
           :pw_note,
           gettext(
             "Your new password is set. Every other session is signed out; this browser stays in. Nothing was mailed to anyone: you changed your own."
           )
         )
         |> mark_saved(gettext("Password changed · just now"))}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:pw_note, nil)
         |> assign(:pw_form, to_form(changeset, as: :pw, action: :validate))}
    end
  end

  # The form always shows what is saved, nothing else: after a
  # successful save it is rebuilt from the persisted user, so a value
  # the database refused can never sit in a field looking saved, and a
  # normalized value (kb for KB) shows as it was stored.
  defp assign_forms(socket, user) do
    socket
    |> assign(:profile_form, to_form(%{"display_name" => user.display_name}, as: :user))
    |> assign(:email_form, to_form(%{"email" => user.email}, as: :em))
    |> assign(:email_moved, false)
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
      waiting={@waiting_comments}
      current_scope={@current_scope}
      crumb={gettext("Your profile")}
      active="profile"
      others={@others}
    >
      <:bar>
        <Layouts.view_site />
      </:bar>
      <div class="admin-col setgrid profile-grid">
        <div class="set-head">
          <h1 class="page-h">{gettext("Your profile")}</h1>
        </div>

        <nav class="setnav profile-nav" aria-label={gettext("Sections")}>
          <a href="#prof-account" aria-current="true">{gettext("Account")}</a>
          <a href="#prof-password">{gettext("Password")}</a>
          <a href="#prof-sessions">{gettext("Your sessions")}</a>
        </nav>

        <div class="setbody">
          <h2 class="set-h" id="prof-account">{gettext("Account")}</h2>
          <.form for={@profile_form} id="profile-form" phx-change="save_profile">
            <div class="drow !mt-0 !pt-0">
              <span class="flex items-baseline justify-between gap-2 pb-[6px]">
                <label
                  class="text-[13.5px] font-medium text-ink"
                  for={@profile_form[:display_name].id}
                >
                  {gettext("Display name")}
                </label>
                <span
                  :if={@saved_at || @saved_note}
                  class="saved num whitespace-nowrap flex-none !text-[12.5px] !m-0 !p-0 !border-0"
                  id="savedProfile"
                  phx-hook="SavedTicker"
                  data-announce="true"
                  data-at={@saved_at}
                  data-note={@saved_note}
                  data-note-until={@saved_note_until}
                  data-saved-label={gettext("Saved")}
                >
                  {gettext("Saved")}
                </span>
              </span>
              <span class="val">
                <input
                  type="text"
                  id={@profile_form[:display_name].id}
                  name={@profile_form[:display_name].name}
                  value={@profile_form[:display_name].value}
                  phx-debounce="300"
                />
                <div class="hint">
                  {gettext("Shown beside your entries and comments. Saves automatically.")}
                </div>
              </span>
            </div>
          </.form>

          <.form
            for={@email_form}
            id="email-form"
            phx-change="email_draft"
            phx-submit="set_email"
            class="mt-5"
          >
            <div class="drow">
              <span class="val">
                <span class="pairrow">
                  <span class="min-w-0">
                    <label class="block text-[13.5px] font-medium text-ink pb-[6px]" for="em-address">
                      {gettext("Email")}
                    </label>
                    <div class={["email-val-row", !@email_moved && "is-resting"]}>
                      <input
                        type="email"
                        id="em-address"
                        name="em[email]"
                        value={@email_form[:email].value}
                        class={!@email_moved && "email-resting"}
                        autocomplete="username"
                        spellcheck="false"
                        autocapitalize="off"
                      />
                      <button
                        :if={!@email_moved}
                        type="button"
                        class="link text-[13px] font-medium whitespace-nowrap flex-none"
                        phx-click={JS.focus(to: "#em-address")}
                      >
                        {gettext("Change email")}
                      </button>
                    </div>
                  </span>
                  <span :if={@email_moved} class="min-w-0">
                    <label class="block text-[13px] font-medium text-ink mb-[6px]" for="em-current">
                      {gettext("Current password")}
                    </label>
                    <input
                      type="password"
                      id="em-current"
                      name="em[current_password]"
                      autocomplete="current-password"
                    />
                  </span>
                  <button
                    :if={@email_moved}
                    class="btn solid w-full sm:w-auto"
                    type="submit"
                    id="em-set"
                  >
                    {gettext("Change email")}
                  </button>
                  <.field_errors field={@email_form[:current_password]} />
                  <.field_errors field={@email_form[:email]} />
                  <div class="hint pairhint">
                    {gettext("You sign in with this address. Changing it requires your password.")}
                  </div>
                </span>
                <p :if={@email_note} class="note mt-[7px]" id="emMeState">{@email_note}</p>
              </span>
            </div>
          </.form>

          <h2 class="set-h" id="prof-password">{gettext("Password")}</h2>
          <.form for={@pw_form} id="password-form" phx-submit="set_password">
            <div class="drow !mt-0 !pt-0">
              <span class="val">
                <span class="pairrow pw-pair">
                  <span class="min-w-0">
                    <label class="block text-[13.5px] font-medium text-ink mb-[6px]" for="pw-current">
                      {gettext("Current password")}
                    </label>
                    <input
                      type="password"
                      id="pw-current"
                      name="pw[current_password]"
                      autocomplete="current-password"
                    />
                  </span>
                  <span class="min-w-0">
                    <label class="block text-[13.5px] font-medium text-ink mb-[6px]" for="pw-new">
                      {gettext("New password")}
                    </label>
                    <input
                      type="password"
                      id="pw-new"
                      name="pw[password]"
                      autocomplete="new-password"
                    />
                  </span>
                  <button class="btn w-full sm:w-auto mt-1" type="submit" id="pw-set">{gettext(
                    "Change password"
                  )}</button>
                  <.field_errors field={@pw_form[:current_password]} />
                  <.field_errors field={@pw_form[:password]} />
                  <div class="hint pairhint">
                    {gettext("At least 12 characters.")}
                  </div>
                </span>
                <p :if={@pw_note} class="note mt-[7px]" id="pwMeState">{@pw_note}</p>
              </span>
            </div>
          </.form>

          <h2 class="set-h" id="prof-sessions">{gettext("Your sessions")}</h2>
          <div id="sessions">
            <div
              :for={session <- @sessions}
              class={[
                "flex items-center gap-3 text-[14px]",
                length(@sessions) > 1 && "py-[11px] border-b border-hair first:pt-0"
              ]}
            >
              <span class="flex-1 min-w-0">
                {gettext("%{browser} · signed in %{when}",
                  browser: session_label(session, @current_scope),
                  when: signed_in_on(session)
                )}
              </span>
            </div>
          </div>
          <p class="note mt-2">
            {gettext("Sign out ends this session only.")}
            <span :if={length(@sessions) > 1}>
              {gettext("Sign out everywhere ends all of them, in every browser.")}
            </span>
          </p>
          <p class="mt-4 flex flex-col sm:flex-row sm:flex-wrap gap-2">
            <.link href={~p"/logout"} method="delete" class="btn w-full sm:w-auto" id="sign-out">
              {gettext("Sign out")}
            </.link>
            <.link
              :if={length(@sessions) > 1}
              href={~p"/logout/all"}
              method="delete"
              class="btn w-full sm:w-auto"
              id="sign-out-all"
            >
              {gettext("Sign out everywhere")}
            </.link>
          </p>
        </div>
      </div>
    </Layouts.app>
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
    if session.token_hash == Accounts.session_fingerprint(scope.session_token),
      do: gettext("This browser"),
      else: gettext("Another browser")
  end

  defp signed_in_on(session) do
    date = DateTime.to_date(session.inserted_at)

    case Date.diff(Date.utc_today(), date) do
      0 -> gettext("today")
      1 -> gettext("yesterday")
      _ -> Date.to_string(date)
    end
  end
end
