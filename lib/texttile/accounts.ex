defmodule Texttile.Accounts do
  @moduledoc """
  Admin accounts, sign-in and sessions.

  There is no public registration. The configuration names everybody who
  may have an account (ADMIN_USERS, see `Texttile.Config.admin_users/1`),
  and a name on that list becomes an account at its first sign-in, with
  the password its owner chooses there.

  The list stays in charge afterwards. Every sign-in, and every request
  of a signed-in browser, asks it again: take a name out and its access
  ends at once, whether or not the account is still there.
  """

  import Ecto.Query

  alias Texttile.Accounts.{Session, User}
  alias Texttile.Repo

  ## The configured admins

  @doc "The usernames that may have an account."
  def admin_usernames, do: Application.get_env(:texttile, :admin_users, [])

  @doc "Whether this name is one of them."
  def admin_username?(username) when is_binary(username) do
    normalize(username) in admin_usernames()
  end

  def admin_username?(_username), do: false

  @doc """
  What the sign-in screen does with a name:

    * `:known` for a configured name that has an account, so ask for the
      password;
    * `:claimable` for a configured name without one, so offer the
      password screen that creates it;
    * `:unknown` for everything else, which the screen answers the same
      way as a wrong password.
  """
  def sign_in_state(username) when is_binary(username) do
    cond do
      not admin_username?(username) -> :unknown
      get_user_by_username(username) -> :known
      true -> :claimable
    end
  end

  @doc """
  Creates the account of a configured name, with the password its owner
  chose. Refuses a name that is not configured (`:not_allowed`) and a
  name that has an account already (`:taken`).
  """
  def claim_account(username, password, password_confirmation \\ nil)
      when is_binary(username) and is_binary(password) do
    attrs = %{
      username: normalize(username),
      password: password,
      password_confirmation: password_confirmation || password
    }

    # The check and the insert share one transaction, so two overlapping
    # claims of one name cannot both create an account.
    result =
      Repo.transaction(fn ->
        case sign_in_state(username) do
          :claimable ->
            case Repo.insert(User.claim_changeset(%User{}, attrs)) do
              {:ok, user} -> user
              {:error, changeset} -> Repo.rollback(changeset)
            end

          :known ->
            Repo.rollback(:taken)

          :unknown ->
            Repo.rollback(:not_allowed)
        end
      end)

    with {:ok, user} <- result do
      broadcast_users_changed()
      {:ok, user}
    end
  end

  ## Sign-in

  @doc """
  Finds the user for a username (any case) and verifies the password.
  Runs the hash either way, so a missing account, and a name the
  configuration does not carry, take as long as a wrong password.
  """
  def authenticate_user(username, password)
      when is_binary(username) and is_binary(password) do
    user = if admin_username?(username), do: get_user_by_username(username)

    if User.valid_password?(user, password), do: {:ok, user}, else: :error
  end

  defp get_user_by_username(username), do: Repo.get_by(User, username: normalize(username))

  defp normalize(username), do: username |> String.trim() |> String.downcase()

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

  @doc """
  The user a live session token belongs to, or nil. A name that left the
  configuration is nobody here, so the browser it left open is out on
  its next request.
  """
  def get_user_by_session_token(token) do
    user =
      Repo.one(
        from s in Session,
          join: u in assoc(s, :user),
          where: s.token == ^token,
          where: s.inserted_at > ago(@session_validity_in_days, "day"),
          select: u
      )

    if user && admin_username?(user.username), do: user
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

  ## Everybody's accounts

  @doc "Every account, the oldest first. All of them are admins, all equal."
  def list_users do
    Repo.all(from u in User, order_by: u.id)
  end

  @doc "Subscribes the caller to `:users_changed` messages."
  def subscribe_users do
    Phoenix.PubSub.subscribe(Texttile.PubSub, "users")
  end

  defp broadcast_users_changed do
    Phoenix.PubSub.broadcast(Texttile.PubSub, "users", :users_changed)
  end

  @doc """
  The one place the deletion rules live. Why this account cannot be
  deleted right now: `:last` while it is the only one (the site would
  have nobody left who can sign in), `:yourself` because somebody else
  removes your account, not you. Or nil, and the delete may go ahead.
  `total` is the current number of accounts, so a screen that already
  holds the list does not ask the database again per row.
  """
  def delete_user_block(%User{} = user, %User{} = by, total) do
    cond do
      total <= 1 -> :last
      user.id == by.id -> :yourself
      true -> nil
    end
  end

  @doc """
  Deletes an account, with its sessions, under the rules of
  `delete_user_block/3`. What the person wrote stays; it belongs to the
  site. An account that another admin deleted first answers `:gone`
  instead of raising. The name keeps its place in the configuration, so
  it can start over with a fresh password.
  """
  def delete_user(%User{} = user, by: %User{} = by) do
    case delete_user_block(user, by, Repo.aggregate(User, :count)) do
      nil ->
        result =
          Repo.transaction(fn ->
            case Repo.get(User, user.id) do
              nil ->
                Repo.rollback(:gone)

              fresh ->
                Repo.delete_all(from s in Session, where: s.user_id == ^fresh.id)
                Repo.delete!(fresh)
            end
          end)

        with {:ok, deleted} <- result do
          broadcast_sessions_changed(deleted.id)
          broadcast_users_changed()
          {:ok, deleted}
        end

      reason ->
        {:error, reason}
    end
  end

  ## Profile

  def get_user!(id), do: Repo.get!(User, id)

  @doc "The user behind an id, or nil when another admin deleted it first."
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Renames the account. The new name has to stand in the configuration
  too, otherwise the rename would sign its owner out of their own
  account on the next request.
  """
  def update_username(user, username) do
    changeset = User.username_changeset(user, %{username: username})

    if admin_username?(to_string(username)) do
      changeset |> Repo.update() |> tap_users_changed()
    else
      {:error,
       changeset
       |> Ecto.Changeset.add_error(:username, "is not a username this server allows")
       |> Map.put(:action, :update)}
    end
  end

  def update_display_name(user, display_name) do
    user
    |> User.display_name_changeset(%{display_name: display_name})
    |> Repo.update()
    |> tap_users_changed()
  end

  def update_email(user, email) do
    user
    |> User.email_changeset(%{email: email})
    |> Repo.update()
    |> tap_users_changed()
  end

  # A profile edit is also a users-list edit: the Settings screen of
  # every admin shows these fields.
  defp tap_users_changed({:ok, _} = result) do
    broadcast_users_changed()
    result
  end

  defp tap_users_changed(result), do: result

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
end
