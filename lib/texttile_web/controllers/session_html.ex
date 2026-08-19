defmodule TexttileWeb.SessionHTML do
  @moduledoc """
  The sign-in screen. The identity you sign in with is your email
  address. Readers never see it.
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
        class="mt-[26px]"
      >
        <div class="mb-[15px]">
          <label class="lab block mb-0" for="login-email">{gettext("Email address")}</label>
          <input
            type="email"
            id="login-email"
            name="user[email]"
            value={@email}
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
        <%!-- The sign-in lasts two days. This makes it fourteen, on
             this browser only. --%>
        <label class="opt">
          <input
            type="checkbox"
            id="login-remember"
            name="user[remember]"
            value="true"
            checked={@remember}
          />
          <span>
            {gettext("Stay signed in on this browser")}
            <span class="note">{gettext("Fourteen days instead of two.")}</span>
          </span>
        </label>
        <button class="btn solid w-full h-[38px] mt-[13px]" type="submit">
          {gettext("Sign in")}
        </button>
      </.form>
      <p :if={@error == :missing} class="text-julia text-[13px] mt-[13px]" id="login-error">
        {gettext("Type your email address and your password. Both fields are required.")}
      </p>
      <p :if={@error == :bad} class="text-julia text-[13px] mt-[13px]" id="login-error">
        {gettext("The address and the password do not match.")}
      </p>
      <p :if={@error == :too_many} class="text-julia text-[13px] mt-[13px]" id="login-error">
        {gettext("Too many tries. Wait a minute, then try again.")}
      </p>
      <p class="mt-[13px]">
        <a class="link text-[13px]" href={~p"/forgot"}>{gettext("Forgot your password?")}</a>
      </p>
      <%!-- Nothing is given away here: while this stands, there is no
           account whose existence it could give away. --%>
      <p :if={@nobody_can_sign_in} class="note mt-[22px] leading-[1.6]" id="login-nobody">
        {gettext(
          "No account here has a password yet. The addresses in ADMIN_USERS have been mailed a link that sets one. While nobody can sign in, the server writes that link into its own log as well, so an installation whose mail does not leave still lets its first admin in."
        )}
      </p>
      <p :if={not @nobody_can_sign_in} class="note mt-[22px] leading-[1.6]">
        {gettext(
          "This page is for admins, and there is no public registration. You sign in with the address your account was invited to, and readers never see it. An admin who is already in invites the next one from Settings."
        )}
      </p>
    </Layouts.auth>
    """
  end
end
