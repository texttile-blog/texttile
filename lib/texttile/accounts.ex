defmodule Texttile.Accounts do
  @moduledoc """
  Admin accounts, sign-in and sessions.

  There is no public registration. The first account is created on the
  setup screen, and only within a short window after boot; every later
  account is created by an admin.
  """

  import Ecto.Query

  alias Texttile.Accounts.{Session, User, UserNotifier}
  alias Texttile.Boot
  alias Texttile.Repo

  @setup_window_ms 30 * 60 * 1000

  ## First-run setup

  @doc """
  Where the first-run setup stands: `:open` while there is no account
  and the window since boot is still open, `:closed` when the window
  ran out first, `:done` once an account exists.
  """
  def setup_state do
    cond do
      any_user?() -> :done
      setup_window_open?() -> :open
      true -> :closed
    end
  end

  defp setup_window_open? do
    case Boot.uptime_ms() do
      ms when is_integer(ms) -> ms < @setup_window_ms
      _never_recorded -> false
    end
  end

  @doc """
  Creates the first admin account and sends the registration
  confirmation to its address. Refuses with `{:error, :done}` once any
  account exists and with `{:error, :closed}` outside the setup window.
  """
  def create_first_admin(attrs, opts) do
    site = Keyword.fetch!(opts, :site)

    # The state check and the insert share one transaction, so two
    # overlapping submissions cannot both become the first admin.
    result =
      Repo.transaction(fn ->
        case setup_state() do
          :open ->
            case insert_user(attrs) do
              {:ok, user} -> user
              {:error, changeset} -> Repo.rollback(changeset)
            end

          other ->
            Repo.rollback(other)
        end
      end)

    case result do
      {:ok, user} ->
        UserNotifier.deliver_registration_confirmation(user, site)
        {:ok, user}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc false
  # Bare insert, also used by fixtures. Setup rules live in
  # create_first_admin/2.
  def insert_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  ## Sign-in

  @doc """
  Finds the user for a username (any case) and verifies the password.
  Runs the hash either way, so a missing account takes as long as a
  wrong password.
  """
  def authenticate_user(username, password)
      when is_binary(username) and is_binary(password) do
    user = Repo.get_by(User, username: username |> String.trim() |> String.downcase())

    if User.valid_password?(user, password), do: {:ok, user}, else: :error
  end

  ## Sessions

  # A token this old no longer signs anybody in.
  @session_validity_in_days 60

  @doc "Opens a session for the user and returns its token."
  def create_session(user) do
    Repo.delete_all(
      from s in Session, where: s.inserted_at < ago(@session_validity_in_days, "day")
    )

    token = Repo.insert!(Session.build(user)).token
    broadcast_sessions_changed(user.id)
    token
  end

  @doc "The user a live session token belongs to, or nil."
  def get_user_by_session_token(token) do
    Repo.one(
      from s in Session,
        join: u in assoc(s, :user),
        where: s.token == ^token,
        where: s.inserted_at > ago(@session_validity_in_days, "day"),
        select: u
    )
  end

  @doc "All live sessions of the user, newest first."
  def list_sessions(user) do
    Repo.all(
      from s in Session,
        where: s.user_id == ^user.id,
        where: s.inserted_at > ago(@session_validity_in_days, "day"),
        order_by: [desc: s.id]
    )
  end

  @doc "Ends the session behind the token. Unknown tokens are fine."
  def delete_session(token) do
    session = Repo.one(from s in Session, where: s.token == ^token)

    if session do
      Repo.delete_all(from s in Session, where: s.token == ^token)
      broadcast_sessions_changed(session.user_id)
    end

    :ok
  end

  @doc """
  Ends every session of the user except the given one. This is what a
  password change does: only the browser that changed it stays in.
  """
  def delete_sessions_except(user, token) do
    Repo.delete_all(from s in Session, where: s.user_id == ^user.id and s.token != ^token)
    broadcast_sessions_changed(user.id)
    :ok
  end

  @doc "The PubSub topic that announces session changes of one user."
  def sessions_topic(user_id), do: "user_sessions:#{user_id}"

  defp broadcast_sessions_changed(user_id) do
    Phoenix.PubSub.broadcast(Texttile.PubSub, sessions_topic(user_id), :sessions_changed)
  end

  ## Profile

  def get_user!(id), do: Repo.get!(User, id)

  def update_username(user, username) do
    user
    |> User.username_changeset(%{username: username})
    |> Repo.update()
  end

  def update_display_name(user, display_name) do
    user
    |> User.display_name_changeset(%{display_name: display_name})
    |> Repo.update()
  end

  def update_email(user, email) do
    user
    |> User.email_changeset(%{email: email})
    |> Repo.update()
  end

  @doc """
  Sets a new password after checking the current one against a fresh
  read of the account, so a LiveView that mounted before an earlier
  change cannot authorize with a superseded password. Ending the other
  sessions is the caller's decision, not this function's.
  """
  def update_password(user, current_password, new_password) do
    user = get_user!(user.id)
    changeset = User.password_changeset(user, %{password: new_password})

    if User.valid_password?(user, current_password) do
      Repo.update(changeset)
    else
      {:error,
       changeset
       |> Ecto.Changeset.add_error(:current_password, "is not your current password")
       |> Map.put(:action, :update)}
    end
  end

  @doc "The name others read: the displayed name, or the username while it is blank."
  def display_name(user) do
    case user.display_name && String.trim(user.display_name) do
      nil -> user.username
      "" -> user.username
      name -> name
    end
  end

  defp any_user? do
    Repo.exists?(User)
  end
end
