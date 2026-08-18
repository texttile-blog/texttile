defmodule TexttileWeb.ProfileLive do
  @moduledoc """
  Your profile: your name, your address, your password, your open
  sessions. The displayed name has no Save button; it applies the
  moment you type it, and the Last-saved line in the corner keeps
  itself current. The address and the password are the two that ask
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
      |> mark_saved(nil)

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
      crumb={gettext("Your profile")}
      active="profile"
      others={@others}
    >
      <:bar>
        <span
          class="text-[12.5px] text-faint num whitespace-nowrap flex-none max-w-[42vw] md:max-w-none overflow-hidden text-ellipsis"
          id="savedProfile"
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
        <h1 class="page-h">{gettext("Your profile")}</h1>
        <p class="lead">
          {gettext("You are signed in as")}
          <b id="profileWho">{Accounts.display_name(@current_scope.user)}</b>. {gettext(
            "Change here your name, your address, your password and your open sessions. Your address and your password need your password once, because whoever holds them holds the account."
          )}
        </p>

        <h2 class="set-h">{gettext("You")}</h2>
        <%!-- fields to type into, so they look like fields; the same
             treatment the Site block of Settings wears --%>
        <.form for={@profile_form} id="profile-form" phx-change="save_profile">
          <div class="drow">
            <label class="lab" for={@profile_form[:display_name].id}>
              {gettext("Displayed name")}
            </label>
            <span class="val">
              <input
                type="text"
                id={@profile_form[:display_name].id}
                name={@profile_form[:display_name].name}
                value={@profile_form[:display_name].value}
                phx-debounce="300"
              />
              <div class="hint">
                {gettext("What others see. Empty shows the part of your address in front of the @.")}
              </div>
            </span>
          </div>
        </.form>

        <%!-- The one field on this screen that does not save itself.
             The address is the identity, so it asks for the password
             the way the password itself does. --%>
        <h2 class="set-h">{gettext("Email")}</h2>
        <.form for={@email_form} id="email-form" phx-submit="set_email">
          <div class="drow">
            <span class="val">
              <span class="flex items-end gap-[10px] flex-wrap">
                <span class="flex-1 min-w-[180px] max-w-[260px]">
                  <label class="block text-[12px] text-dim mb-[3px]" for="em-address">
                    {gettext("Address")}
                  </label>
                  <input
                    type="email"
                    id="em-address"
                    name="em[email]"
                    value={@email_form[:email].value}
                    autocomplete="username"
                    spellcheck="false"
                    autocapitalize="off"
                  />
                </span>
                <span class="flex-1 min-w-[180px] max-w-[260px]">
                  <label class="block text-[12px] text-dim mb-[3px]" for="em-current">
                    {gettext("Your password")}
                  </label>
                  <input
                    type="password"
                    id="em-current"
                    name="em[current_password]"
                    autocomplete="current-password"
                  />
                </span>
                <button class="btn" type="submit" id="em-set">{gettext("Change")}</button>
              </span>
              <.field_errors field={@email_form[:current_password]} />
              <.field_errors field={@email_form[:email]} />
              <div class="hint">
                {gettext(
                  "This is what you sign in with, and where password links go. Readers never see it. Changing it needs your password, because whoever holds the address holds the account."
                )}
              </div>
              <p :if={@email_note} class="note mt-[7px]" id="emMeState">{@email_note}</p>
            </span>
          </div>
        </.form>

        <h2 class="set-h">{gettext("Password")}</h2>
        <.form for={@pw_form} id="password-form" phx-submit="set_password">
          <div class="drow">
            <span class="val">
              <span class="flex items-end gap-[10px] flex-wrap">
                <span class="flex-1 min-w-[180px] max-w-[260px]">
                  <label class="block text-[12px] text-dim mb-[3px]" for="pw-current">
                    {gettext("Current password")}
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
                    {gettext("New password")}
                  </label>
                  <input
                    type="password"
                    id="pw-new"
                    name="pw[password]"
                    autocomplete="new-password"
                  />
                </span>
                <button class="btn" type="submit">{gettext("Set")}</button>
              </span>
              <.field_errors field={@pw_form[:current_password]} />
              <.field_errors field={@pw_form[:password]} />
              <div class="hint">
                {gettext(
                  "Confirm the current password once to change it. Needs to be at least 12 characters."
                )}
              </div>
              <p :if={@pw_note} class="note mt-[7px]" id="pwMeState">{@pw_note}</p>
            </span>
          </div>
        </.form>

        <h2 class="set-h">{gettext("Your sessions")}</h2>
        <div id="sessions">
          <div
            :for={session <- @sessions}
            class="flex items-center gap-3 py-[13px] border-b border-hair text-[13.5px]"
          >
            <span class="flex-1 min-w-0">
              {gettext("%{browser} · signed in %{when}",
                browser: session_label(session, @current_scope),
                when: signed_in_on(session)
              )}
            </span>
            <span :if={length(@sessions) == 1} class="note">{gettext("the only one open")}</span>
          </div>
        </div>
        <p class="note mt-3">
          {gettext("Sign out ends this session only.")}<span :if={length(@sessions) > 1}>
            {gettext("Sign out everywhere ends all of them, in every browser.")}</span>
        </p>
        <p class="mt-4 flex gap-2">
          <.link href={~p"/logout"} method="delete" class="btn" id="sign-out">
            {gettext("Sign out")}
          </.link>
          <.link
            :if={length(@sessions) > 1}
            href={~p"/logout/all"}
            method="delete"
            class="btn"
            id="sign-out-all"
          >
            {gettext("Sign out everywhere")}
          </.link>
        </p>
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
