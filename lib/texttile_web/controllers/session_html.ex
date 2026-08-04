defmodule TexttileWeb.SessionHTML do
  @moduledoc """
  The sign-in screen. The identity you sign in with is the username.
  The email address is only where links and notifications go.
  """
  use TexttileWeb, :html

  def new(assigns) do
    ~H"""
    <Layouts.auth subtitle={"Admin sign-in · #{@conn.host}"}>
      <.form
        :let={_f}
        for={%{}}
        as={:user}
        action={~p"/login"}
        id="login-form"
        class="quiet-fields mt-[26px]"
      >
        <div class="mb-[15px]">
          <label class="lab block mb-0" for="login-username">Username</label>
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
          <label class="lab block mb-0" for="login-password">Password</label>
          <input
            type="password"
            id="login-password"
            name="user[password]"
            autocomplete="current-password"
          />
        </div>
        <button class="btn solid w-full h-[38px] mt-[6px]" type="submit">Sign in</button>
      </.form>
      <p :if={@error == :missing} class="text-julia text-[13px] mt-[13px]" id="login-error">
        Type your username and your password. Both fields are required.
      </p>
      <p :if={@error == :bad} class="text-julia text-[13px] mt-[13px]" id="login-error">
        The username and the password do not match.
      </p>
      <p :if={@error == :claimed} class="text-julia text-[13px] mt-[13px]" id="login-error">
        This account already exists. Sign in with its password.
      </p>
      <p class="note mt-[22px] leading-[1.6]">
        This page is for admins. Readers never see it, and there is no public
        registration. The people who may sign in stand in the configuration of
        this server. Each of them chooses a password at the first sign-in. Your
        username is the name you sign in with. Your email address is only for
        notifications, and you add it in your profile.
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
    <Layouts.auth subtitle={"First sign-in · #{@conn.host}"}>
      <h2 class="font-serif text-[19px] font-semibold tracking-[-.01em] mt-[22px]">
        Choose a password
      </h2>
      <p class="text-[13.5px] mt-[9px] leading-[1.6]">
        The name <strong>{@username}</strong>
        has no account yet. The password you type here becomes its password,
        and the account is yours from then on.
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
          <label class="lab block mb-0" for="claim-password">Password</label>
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
            Repeat the password
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
          <span class="note">At least 12 characters. Nothing else is required.</span>
          <span class="sp"></span>
          <button class="link text-[12.5px]" type="button" data-toggle-password="claim-password">
            Show
          </button>
        </div>
        <button class="btn solid w-full h-[38px] mt-[16px]" type="submit">
          Create the account and sign in
        </button>
      </.form>
      <p class="note mt-[22px] leading-[1.6]">
        Keep this password. No mail goes out about it, and nobody can send you
        a new one: the account has no address until you add one in your
        profile.
      </p>
      <p class="note mt-[10px]">
        <.link href={~p"/login"} class="link" id="claim-back">Sign in with another name</.link>
      </p>
    </Layouts.auth>
    """
  end

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

  defp errors_for(changeset, field) do
    for {^field, {message, opts}} <- changeset.errors do
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end
  end
end
