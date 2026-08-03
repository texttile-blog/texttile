defmodule TexttileWeb.SetupHTML do
  @moduledoc """
  First-run setup, in the language of the sign-in family. The screen is
  only open for a short window after boot; after that it says so and
  asks for a restart.
  """
  use TexttileWeb, :html

  def new(assigns) do
    ~H"""
    <Layouts.auth subtitle={"First-run setup · #{@conn.host}"}>
      <p class="text-[13.5px] mt-[20px] leading-[1.6]">
        This server runs for the first time and has no admin yet. Create the
        first account here. This screen is open for 30 minutes after the
        start; after that, a restart opens it again.
      </p>
      <.form
        :let={_f}
        for={%{}}
        as={:user}
        action={~p"/setup"}
        id="setup-form"
        class="quiet-fields mt-[18px]"
      >
        <div class="mb-[15px]">
          <label class="lab block mb-0" for="setup-username">Username</label>
          <input
            type="text"
            id="setup-username"
            name="user[username]"
            value={value(@changeset, :username)}
            autocomplete="username"
            spellcheck="false"
            autocapitalize="off"
            autocorrect="off"
            autofocus
          />
          <.field_error changeset={@changeset} field={:username} />
        </div>
        <div class="mb-[15px]">
          <label class="lab block mb-0" for="setup-email">Email address</label>
          <input
            type="email"
            id="setup-email"
            name="user[email]"
            value={value(@changeset, :email)}
            autocomplete="email"
          />
          <.field_error changeset={@changeset} field={:email} />
        </div>
        <div class="mb-[7px]">
          <label class="lab block mb-0" for="setup-password">Password</label>
          <input
            type="password"
            id="setup-password"
            name="user[password]"
            autocomplete="new-password"
          />
          <.field_error changeset={@changeset} field={:password} />
        </div>
        <div class="flex items-baseline gap-[10px]">
          <span class="note">At least 12 characters. Nothing else is required.</span>
          <span class="sp"></span>
          <button
            class="link text-[12.5px]"
            type="button"
            data-toggle-password="setup-password"
          >
            Show
          </button>
        </div>
        <button class="btn solid w-full h-[38px] mt-[16px]" type="submit">
          Create the account and sign in
        </button>
      </.form>
      <p class="note mt-[22px] leading-[1.6]">
        A confirmation mail goes to your address: which site, which username.
        It never contains the password, and no mail ever will. More admins are
        invited later, in Settings.
      </p>
    </Layouts.auth>
    """
  end

  def closed(assigns) do
    ~H"""
    <Layouts.auth subtitle={"First-run setup · #{@conn.host}"}>
      <h2 class="font-serif text-[19px] font-semibold tracking-[-.01em] mt-[22px]">
        The setup window is closed
      </h2>
      <p class="text-[13.5px] mt-[9px] leading-[1.6]">
        Setup is only open for 30 minutes after the server starts. This server
        runs longer than that, and no admin account exists yet.
      </p>
      <p class="note mt-[10px] leading-[1.6]">
        Restart the server. The window opens again, and this screen becomes
        the setup form.
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

  defp value(nil, _field), do: nil
  defp value(changeset, field), do: Ecto.Changeset.get_field(changeset, field)

  defp errors_for(nil, _field), do: []

  defp errors_for(changeset, field) do
    for {^field, {message, opts}} <- changeset.errors do
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end
  end
end
