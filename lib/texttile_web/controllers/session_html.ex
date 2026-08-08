defmodule TexttileWeb.SessionHTML do
  @moduledoc """
  The sign-in screen. The identity you sign in with is the username.
  The email address is only where links and notifications go.
  """
  use TexttileWeb, :html

  def new(assigns) do
    ~H"""
    <Layouts.auth subtitle={gettext("Admin sign-in · %{host}", host: @conn.host)}>
      <.form
        :let={_f}
        for={%{}}
        as={:user}
        action={~p"/login"}
        id="login-form"
        class="quiet-fields mt-[26px]"
      >
        <div class="mb-[15px]">
          <label class="lab block mb-0" for="login-username">{gettext("Username")}</label>
          <input
            type="text"
            id="login-username"
            name="user[username]"
            value={@username}
            autocomplete="username"
            spellcheck="false"
            autocapitalize="off"
            autocorrect="off"
            autofocus
          />
        </div>
        <div class="mb-[15px]">
          <label class="lab block mb-0" for="login-password">{gettext("Password")}</label>
          <input
            type="password"
            id="login-password"
            name="user[password]"
            autocomplete="current-password"
          />
        </div>
        <button class="btn solid w-full h-[38px] mt-[6px]" type="submit">{gettext("Sign in")}</button>
      </.form>
      <p :if={@error == :missing} class="text-julia text-[13px] mt-[13px]" id="login-error">
        {gettext("Type your username and your password. Both fields are required.")}
      </p>
      <p :if={@error == :bad} class="text-julia text-[13px] mt-[13px]" id="login-error">
        {gettext("The username and the password do not match.")}
      </p>
      <p :if={@error == :claimed} class="text-julia text-[13px] mt-[13px]" id="login-error">
        {gettext("This account already exists. Sign in with its password.")}
      </p>
      <p class="mt-[13px]">
        <a class="link text-[13px]" href={~p"/forgot"}>{gettext("Forgot your password?")}</a>
      </p>
      <p class="note mt-[22px] leading-[1.6]">
        {gettext(
          "This page is for admins. Readers never see it, and there is no public registration. The people who may sign in stand in the configuration of this server. Each of them chooses a password at the first sign-in. Your username is the name you sign in with. Your email address is what a password link needs. You give it at the first sign-in and can change it in your profile."
        )}
      </p>
    </Layouts.auth>
    """
  end

  @doc """
  The password screen: a configured name that has no account signs in
  for the first time and chooses the password of the new account.
  """
  def claim(assigns) do
    ~H"""
    <Layouts.auth subtitle={gettext("First sign-in · %{host}", host: @conn.host)}>
      <h2 class="font-serif text-[19px] font-semibold tracking-[-.01em] mt-[22px]">
        {gettext("Choose a password")}
      </h2>
      <p class="text-[13.5px] mt-[9px] leading-[1.6]">
        {gettext("The name")} <strong>{@username}</strong>
        {gettext(
          "has no account yet. The password you type here becomes its password, and the account is yours from then on."
        )}
      </p>
      <.form
        :let={_f}
        for={%{}}
        as={:user}
        action={~p"/login/claim"}
        id="claim-form"
        class="quiet-fields mt-[18px]"
      >
        <input type="hidden" name="user[username]" value={@username} />
        <div class="mb-[15px]">
          <label class="lab block mb-0" for="claim-password">{gettext("Password")}</label>
          <input
            type="password"
            id="claim-password"
            name="user[password]"
            autocomplete="new-password"
            autofocus
          />
          <.field_error changeset={@changeset} field={:password} />
        </div>
        <div class="mb-[7px]">
          <label class="lab block mb-0" for="claim-password-confirmation">
            {gettext("Repeat the password")}
          </label>
          <input
            type="password"
            id="claim-password-confirmation"
            name="user[password_confirmation]"
            autocomplete="new-password"
          />
          <.field_error changeset={@changeset} field={:password_confirmation} />
        </div>
        <div class="flex items-baseline gap-[10px]">
          <span class="note">{gettext("At least 12 characters.")}</span>
          <span class="sp"></span>
          <button class="link text-[12.5px]" type="button" data-toggle-password="claim-password">
            {gettext("Show")}
          </button>
        </div>
        <div class="mt-[15px] mb-[15px]">
          <label class="lab block mb-0" for="claim-email">{gettext("Email address")}</label>
          <input
            type="email"
            id="claim-email"
            name="user[email]"
            value={value(@changeset, :email)}
            autocomplete="email"
          />
          <.field_error changeset={@changeset} field={:email} />
          <p class="note mt-[6px]">
            {gettext("Where a password reset goes. No account exists without one.")}
          </p>
        </div>
        <div class="mb-[7px]">
          <label class="lab block mb-0" for="claim-display-name">{gettext("Displayed name")}</label>
          <input
            type="text"
            id="claim-display-name"
            name="user[display_name]"
            value={value(@changeset, :display_name)}
            autocomplete="name"
          />
          <.field_error changeset={@changeset} field={:display_name} />
          <p class="note mt-[6px]">{gettext("What readers see. Empty shows your username.")}</p>
        </div>
        <button class="btn solid w-full h-[38px] mt-[16px]" type="submit">
          {gettext("Create the account and sign in")}
        </button>
      </.form>
      <p class="note mt-[22px] leading-[1.6]">
        {gettext(
          "A confirmation mail goes to your address: which site, which username. It never contains the password, and no mail ever will. If you forget the password, the sign-in screen mails your address a link that sets a new one."
        )}
      </p>
      <p class="note mt-[10px]">
        <.link href={~p"/login"} class="link" id="claim-back">
          {gettext("Sign in with another name")}
        </.link>
      </p>
    </Layouts.auth>
    """
  end

  defp value(nil, _field), do: nil
  defp value(changeset, field), do: Ecto.Changeset.get_field(changeset, field)

  attr :changeset, :any, required: true
  attr :field, :atom, required: true

  defp field_error(assigns) do
    ~H"""
    <p :for={message <- errors_for(@changeset, @field)} class="text-julia text-[13px] mt-[6px]">
      {message}
    </p>
    """
  end

  defp errors_for(nil, _field), do: []

  defp errors_for(changeset, field), do: translate_errors(changeset.errors, field)
end
