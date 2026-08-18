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

  alias Texttile.Accounts.{LoginLink, Session, User, UserNotifier}
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

  ## The brake on the password doors

  @doc """
  The limiter in front of every door that takes a password: the
  sign-in, the first sign-in and the site password of the blog. They
  share one bucket per caller, because they are one question asked
  three ways, and a caller who is guessing at one of them has no
  business hammering the next.

  The doors are the one place where a few tries per minute is plenty
  for a person and far too few for a machine. bcrypt already makes the
  sign-in slow; the site password is a short shared word and has
  nothing but this.
  """
  def door_limiter, do: Texttile.Accounts.DoorLimiter

  @doc "How many tries a caller has per minute at the password doors."
  def door_limiter_per_minute, do: 5

  @doc "Whether this installation has any account at all."
  def any_account?, do: Repo.exists?(User)

  @doc """
  Whether this name may choose its password right now without an
  invitation. That is the first account of a fresh installation, and
  only that one: a fresh installation has nobody who could invite.

  Every later name needs an invitation from somebody who is already in,
  because the names are no secret. They stand under the entries they
  wrote, and a name whose owner has not signed in yet would otherwise
  belong to whoever guesses it first.
  """
  def open_claim?(username) when is_binary(username) do
    sign_in_state(username) == :claimable and not any_account?()
  end

  @doc """
  The configured names that have no account yet. Settings offers an
  invitation for each of them.
  """
  def unclaimed_usernames do
    taken = Repo.all(from u in User, select: u.username)
    Enum.reject(admin_usernames(), &(&1 in taken))
  end

  @doc """
  Creates the account of a configured name: the password its owner
  chose, the email address a reset will need, the displayed name.
  Refuses a name that is not configured, and a name that may not be
  claimed right now (`:not_allowed`), and a name that has an account
  already (`:taken`). With a `:site` in the opts, a confirmation goes to
  the address; it never contains the password, and a mail that cannot
  leave does not undo the account.

  `invited: true` says the caller carried a valid invitation. Without
  one, only the first account of an empty installation goes through, see
  `open_claim?/1`.
  """
  def claim_account(username, attrs, opts \\ [])
      when is_binary(username) and is_map(attrs) do
    attrs =
      attrs
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.put("username", normalize(username))

    # The check and the insert share one transaction, so two overlapping
    # claims of one name cannot both create an account.
    result =
      Repo.transaction(fn ->
        case sign_in_state(username) do
          :claimable ->
            if Keyword.get(opts, :invited, false) or not any_account?() do
              case Repo.insert(User.claim_changeset(%User{}, attrs)) do
                {:ok, user} -> user
                {:error, changeset} -> Repo.rollback(changeset)
              end
            else
              Repo.rollback(:not_allowed)
            end

          :known ->
            Repo.rollback(:taken)

          :unknown ->
            Repo.rollback(:not_allowed)
        end
      end)

    with {:ok, user} <- result do
      if site = Keyword.get(opts, :site) do
        _ = UserNotifier.deliver_registration_confirmation(user, site)
      end

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

  # How long a signed-in browser stays signed in. The short span is
  # what a sign-in gets by default; the long one is the box on the form.
  # The span is set once and never moved, so nobody stays in forever by
  # opening the same page every day.
  @session_days 2
  @remember_days 14

  @doc """
  How many seconds a session lasts, and with it the cookie that carries
  it: two days, or fourteen for a browser that is remembered.
  """
  def session_max_age(remember?)
  def session_max_age(true), do: @remember_days * 24 * 60 * 60
  def session_max_age(_other), do: @session_days * 24 * 60 * 60

  @doc """
  Opens a session for the user and returns its token. `remember: true`
  is the box on the sign-in form.
  """
  def create_session(user, opts \\ []) do
    now = moment(opts)
    Repo.delete_all(from s in Session, where: s.expires_at <= ^now)

    expires_at = DateTime.add(now, session_max_age(opts[:remember] == true), :second)
    {token, session} = Session.build(user, expires_at)
    Repo.insert!(session)
    broadcast_sessions_changed(user.id)
    token
  end

  @doc """
  The hash a token from a cookie is stored under. The one name every
  screen knows a session by, because it is the only one the table has.
  """
  def session_fingerprint(token) when is_binary(token), do: Session.hash(token)

  @doc """
  The user a live session token belongs to, or nil. A name that left the
  configuration is nobody here, so the browser it left open is out on
  its next request.
  """
  def get_user_by_session_token(token, opts \\ []) do
    hash = Session.hash(token)

    user =
      Repo.one(
        from s in Session,
          join: u in assoc(s, :user),
          where: s.token_hash == ^hash,
          where: s.expires_at > ^moment(opts),
          select: u
      )

    if user && admin_username?(user.username), do: user
  end

  @doc "All live sessions of the user, newest first."
  def list_sessions(user, opts \\ []) do
    Repo.all(
      from s in Session,
        where: s.user_id == ^user.id,
        where: s.expires_at > ^moment(opts),
        order_by: [desc: s.id]
    )
  end

  @doc "Ends the session behind the token. Unknown tokens are fine."
  def delete_session(token) do
    hash = Session.hash(token)
    session = Repo.one(from s in Session, where: s.token_hash == ^hash)

    if session do
      Repo.delete_all(from s in Session, where: s.token_hash == ^hash)
      broadcast_sessions_changed(session.user_id)
    end

    :ok
  end

  @doc """
  Ends every session of the user, the current one included. This is the
  profile's sign-out-everywhere.
  """
  def delete_all_sessions(user) do
    Repo.delete_all(from s in Session, where: s.user_id == ^user.id)
    broadcast_sessions_changed(user.id)
    :ok
  end

  @doc """
  Ends every session of the user except the given one. This is what a
  password change does: only the browser that changed it stays in.
  """
  def delete_sessions_except(user, token) do
    hash = Session.hash(token)

    Repo.delete_all(from s in Session, where: s.user_id == ^user.id and s.token_hash != ^hash)
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

  ## The mailed password link

  @doc """
  The user behind an email address (any case), or nil. A name the
  configuration no longer carries is nobody, so the Forgot screen does
  not mail it a link either.
  """
  def get_user_by_email(email) when is_binary(email) do
    user = Repo.get_by(User, email: email |> String.trim() |> String.downcase())

    if user && admin_username?(user.username), do: user
  end

  @doc """
  Mails the user a link that sets a new password. The fresh link
  replaces any earlier one. `:link_url` turns the token into the URL for
  the mail; `:site` names the site in it. When the mail cannot leave,
  the answer says so instead of pretending.
  """
  def send_password_link(user, opts) do
    site = Keyword.fetch!(opts, :site)
    link_url = Keyword.fetch!(opts, :link_url)

    {token, link} = LoginLink.build(user)

    {:ok, _} =
      Repo.transaction(fn ->
        Repo.delete_all(from l in LoginLink, where: l.user_id == ^user.id)
        Repo.insert!(link)
      end)

    url = link_url.(token)

    case UserNotifier.deliver_password_reset(user, url, site) do
      {:ok, _} -> {:ok, token}
      {:error, reason} -> {:error, {:mail, reason}}
    end
  end

  @doc """
  True while a link mailed within the last minute is still the newest.
  The public Forgot screen uses this as its brake: whatever a stranger
  hammers into it, one mail per account per minute leaves, and the
  pending link is not churned.
  """
  def link_recently_sent?(user, opts \\ []) do
    minute_ago = DateTime.add(moment(opts), -60, :second)

    Repo.exists?(
      from l in LoginLink,
        where: l.user_id == ^user.id,
        where: l.inserted_at > ^minute_ago
    )
  end

  # A link this old opens nothing.
  @link_validity_in_hours 24

  @doc """
  The user a mailed link belongs to, while the link is fresh. Or
  `:error`. A name that left the configuration owns nothing here any
  more, so its links open nothing either.
  """
  def verify_login_link(token, opts \\ [])

  def verify_login_link(token, opts) when is_binary(token) do
    hash = LoginLink.hash(token)
    oldest = DateTime.add(moment(opts), -@link_validity_in_hours * 3600, :second)

    user =
      Repo.one(
        from l in LoginLink,
          join: u in assoc(l, :user),
          where: l.token_hash == ^hash,
          where: l.inserted_at > ^oldest,
          select: u
      )

    if user && admin_username?(user.username), do: {:ok, user}, else: :error
  end

  @doc """
  Sets the password behind a mailed link. The link is spent with it, and
  every open session of the account ends: whoever holds the new password
  signs in fresh. A refused password leaves the link usable.
  """
  def accept_login_link(token, password, opts \\ []) do
    with {:ok, user} <- verify_login_link(token, opts) do
      result =
        Repo.transaction(fn ->
          case Repo.update(User.password_changeset(user, %{password: password})) do
            {:ok, user} ->
              Repo.delete_all(from l in LoginLink, where: l.user_id == ^user.id)
              Repo.delete_all(from s in Session, where: s.user_id == ^user.id)
              user

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end)

      case result do
        {:ok, user} ->
          broadcast_sessions_changed(user.id)
          broadcast_users_changed()
          {:ok, user}

        {:error, changeset} ->
          {:error, Map.put(changeset, :action, :insert)}
      end
    end
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
  Deletes an account, with its sessions and links, under the rules of
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
                Repo.delete_all(from l in LoginLink, where: l.user_id == ^fresh.id)
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

  # `now:` names the moment a deadline is judged at, so a test can
  # stand on the far side of a session or a link without back-dating
  # rows. Defaults to this moment.
  defp moment(opts) do
    opts
    |> Keyword.get_lazy(:now, fn -> DateTime.utc_now() end)
    |> DateTime.truncate(:second)
  end
end
