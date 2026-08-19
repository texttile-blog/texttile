defmodule TexttileWeb.LinkHTML do
  @moduledoc """
  The three faces of a mailed link: set a new password, ask for a link,
  and the screen a dead link lands on. All of them share the sign-in
  column. Ported from the round-13 prototype.
  """
  use TexttileWeb, :html

  def show(assigns) do
    ~H"""
    <Layouts.auth subtitle={
      if @invitation,
        do: gettext("Your admin account · %{host}", host: @conn.host),
        else: gettext("A new password · %{host}", host: @conn.host)
    }>
      <p :if={@invitation} class="text-[13.5px] mt-[20px] leading-[1.6]" id="link-who">
        {gettext("This link opens the admin account of")} <b>{@user.email}</b>. {gettext(
          "The password you choose here becomes its password, and you sign in with it from then on."
        )}
      </p>
      <p :if={not @invitation} class="text-[13.5px] mt-[20px] leading-[1.6]" id="link-who">
        {gettext("This link belongs to the account")} <b>{@user.email}</b>. {gettext(
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
        <%!-- The name readers see, asked at the one moment its owner
             is at the screen, and first: it is the one field here that
             is about the person, not about getting in. Empty is not an
             answer, because an entry signed with the part in front of
             an @ is a byline nobody chose. --%>
        <div :if={@invitation} class="mb-[15px]">
          <label class="lab block mb-0" for="link-display-name">
            {gettext("Displayed name")}
          </label>
          <input
            type="text"
            id="link-display-name"
            name="user[display_name]"
            value={value(@changeset, :display_name)}
            autocomplete="name"
            autofocus
          />
          <.field_error changeset={@changeset} field={:display_name} />
          <p class="note mt-[6px]">
            {gettext("What readers see under the entries you write. Your address stays private.")}
          </p>
        </div>
        <div class="mb-[7px]">
          <label class="lab block mb-0" for="link-password">
            {if @invitation, do: gettext("Your password"), else: gettext("New password")}
          </label>
          <input
            type="password"
            id="link-password"
            name="user[password]"
            autocomplete="new-password"
            autofocus={not @invitation}
          />
          <.field_error changeset={@changeset} field={:password} />
        </div>
        <%!-- The first password of an account is typed twice: nobody
             knows it yet, and a typo would shut its owner out of the
             account they are opening, with the link spent. --%>
        <div :if={@invitation} class="mb-[7px]">
          <label class="lab block mb-0" for="link-password-confirmation">
            {gettext("Repeat the password")}
          </label>
          <input
            type="password"
            id="link-password-confirmation"
            name="user[password_confirmation]"
            autocomplete="new-password"
          />
          <.field_error changeset={@changeset} field={:password_confirmation} />
        </div>
        <div class="flex items-baseline gap-[10px]">
          <span class="note">
            {if @invitation,
              do: gettext("At least 12 characters, and the same one twice."),
              else: gettext("At least 12 characters. Nothing else is required.")}
          </span>
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
          {if @invitation,
            do: gettext("Open the account and sign in"),
            else: gettext("Set the password and sign in")}
        </button>
      </.form>
      <p :if={@invitation} class="note mt-[22px] leading-[1.6]">
        {gettext(
          "This link works one time, and for a week. Nobody else sets your password, and nobody else can read it."
        )}
      </p>
      <p :if={not @invitation} class="note mt-[22px] leading-[1.6]">
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

  defp value(nil, _field), do: nil
  defp value(changeset, field), do: Ecto.Changeset.get_field(changeset, field)

  attr :changeset, :any, required: true
  attr :field, :atom, required: true

  # A form only carries a changeset after a refused answer, so every
  # error in it is worth showing, under the field it belongs to.
  defp field_error(assigns) do
    ~H"""
    <p :for={message <- errors_for(@changeset, @field)} class="text-julia text-[13px] mt-[6px]">
      {message}
    </p>
    """
  end

  defp errors_for(nil, _field), do: []
  defp errors_for(changeset, field), do: translate_errors(changeset.errors, field)

  def dead(assigns) do
    ~H"""
    <Layouts.auth subtitle={gettext("A new password · %{host}", host: @conn.host)}>
      <h2 class="font-serif text-[19px] font-semibold tracking-[-.01em] mt-[22px]">
        {gettext("This link does not work any more")}
      </h2>
      <p class="text-[13.5px] mt-[9px] leading-[1.6]">
        {gettext(
          "A link to set a password works one time: a day for a password reset, a week for an invitation. Somebody used this one already, or it is older than that."
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
