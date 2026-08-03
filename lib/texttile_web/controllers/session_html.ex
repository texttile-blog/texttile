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
      <p class="note mt-[22px] leading-[1.6]">
        This page is for admins. Readers never see it, and there is no public
        registration. An admin invites new people in Settings. Each person sets
        their own password at the first sign-in. Your username is the name you
        sign in with. Your email address is only for notifications and password
        links.
      </p>
    </Layouts.auth>
    """
  end
end
