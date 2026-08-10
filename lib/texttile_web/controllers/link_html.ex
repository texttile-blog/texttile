defmodule TexttileWeb.LinkHTML do
  @moduledoc """
  The three faces of a mailed link: set a new password, ask for a link,
  and the screen a dead link lands on. All of them share the sign-in
  column. Ported from the round-13 prototype.
  """
  use TexttileWeb, :html

  def show(assigns) do
    ~H"""
    <Layouts.auth subtitle={gettext("A new password · %{host}", host: @conn.host)}>
      <p class="text-[13.5px] mt-[20px] leading-[1.6]" id="link-who">
        {gettext("This link belongs to the account")} <b>{@user.username}</b>, {@user.email}. {gettext(
          "The old password stops working the moment you set a new one."
        )}
      </p>
      <.form
        :let={_f}
        for={%{}}
        as={:user}
        action={~p"/link/#{@token}"}
        id="set-password-form"
        class="mt-[18px]"
      >
        <div class="mb-[7px]">
          <label class="lab block mb-0" for="link-password">{gettext("New password")}</label>
          <input
            type="password"
            id="link-password"
            name="user[password]"
            autocomplete="new-password"
            autofocus
          />
        </div>
        <div class="flex items-baseline gap-[10px]">
          <span class="note">{gettext("At least 12 characters. Nothing else is required.")}</span>
          <span class="sp"></span>
          <button
            class="link text-[12.5px]"
            type="button"
            tabindex="-1"
            data-toggle-password="link-password"
          >
            {gettext("Show")}
          </button>
        </div>
        <button class="btn solid w-full h-[38px] mt-[16px]" type="submit">
          {gettext("Set the password and sign in")}
        </button>
      </.form>
      <p :if={@error} class="text-julia text-[13px] mt-[13px]" id="link-error">
        {String.capitalize(@error)}.
      </p>
      <p class="note mt-[22px] leading-[1.6]">
        {gettext(
          "This link works one time, and for 24 hours. Nobody else sets your password, and nobody else can read it."
        )}
      </p>
      <p class="mt-[13px]">
        <a class="link text-[13px]" href={~p"/login"}>{gettext("Back to sign-in")}</a>
      </p>
    </Layouts.auth>
    """
  end

  def dead(assigns) do
    ~H"""
    <Layouts.auth subtitle={gettext("A new password · %{host}", host: @conn.host)}>
      <h2 class="font-serif text-[19px] font-semibold tracking-[-.01em] mt-[22px]">
        {gettext("This link does not work any more")}
      </h2>
      <p class="text-[13.5px] mt-[9px] leading-[1.6]">
        {gettext(
          "A link to set a password works one time, and for 24 hours. Somebody used this one already, or it is older than a day."
        )}
      </p>
      <p class="note mt-[10px] leading-[1.6]">
        {gettext("Ask for a new one and it arrives in the same inbox. The old link stays dead.")}
      </p>
      <p class="flex gap-2 mt-[20px]">
        <a class="btn solid" href={~p"/forgot"}>{gettext("Request a new link")}</a>
        <a class="btn quiet" href={~p"/login"}>{gettext("Back to sign-in")}</a>
      </p>
    </Layouts.auth>
    """
  end

  def forgot(assigns) do
    ~H"""
    <Layouts.auth subtitle={gettext("A new password · %{host}", host: @conn.host)}>
      <%= if @sent do %>
        <p class="text-[13.5px] mt-[20px] leading-[1.6]" id="forgot-sent">
          {gettext(
            "The mail is on its way, if an account uses that address. Open it and follow the link."
          )}
        </p>
        <p class="note mt-[10px] leading-[1.6]">
          {gettext(
            "This screen never says whether an address has an account. The link works one time, and for 24 hours. No mail arrives for an address without an account."
          )}
        </p>
      <% else %>
        <p class="text-[13.5px] mt-[20px] leading-[1.6]">
          {gettext(
            "Type the email address of your account. A link to set a new password goes to that address."
          )}
        </p>
        <.form
          :let={_f}
          for={%{}}
          as={:user}
          action={~p"/forgot"}
          id="forgot-form"
          class="mt-[18px]"
        >
          <div class="mb-[15px]">
            <label class="lab block mb-0" for="forgot-email">{gettext("Email address")}</label>
            <input type="email" id="forgot-email" name="user[email]" autocomplete="email" autofocus />
          </div>
          <button class="btn solid w-full h-[38px] mt-[6px]" type="submit">
            {gettext("Send the link")}
          </button>
        </.form>
      <% end %>
      <p class="mt-[20px]">
        <a class="link text-[13px]" href={~p"/login"}>{gettext("Back to sign-in")}</a>
      </p>
    </Layouts.auth>
    """
  end
end
