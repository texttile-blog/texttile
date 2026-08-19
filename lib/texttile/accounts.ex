defmodule Texttile.Accounts do
  @moduledoc """
  Admin accounts, sign-in and sessions.

  The accounts are the guest list: this table says who may sign in, and
  the address is the identity. There is no public registration and
  nothing to guess.

  An account comes into being in one of two ways, and both of them end
  in a mail. An address in ADMIN_USERS that has no account gets one at
  the start of the server (see `invite_configured/1`). An admin who is
  already in types an address into Settings. Either way the owner of
  that inbox opens a link and sets the password, so the proof of who you
  are is the inbox, not a name somebody handed over.

  Taking access away means deleting the account. An address out of
  ADMIN_USERS takes nothing back: what it once made, it made.
  """

  import Ecto.Query

  require Logger

  alias Texttile.Accounts.{LoginLink, Session, User, UserNotifier}
  alias Texttile.Repo
  alias Texttile.Settings

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

  ## Invitations

  @doc "The addresses ADMIN_USERS makes an account for."
  def admin_emails, do: Application.get_env(:texttile, :admin_emails, [])

  @doc "Whether this installation has any account at all."
  def any_account?, do: Repo.exists?(User)

  @doc """
  Whether nobody can sign in here yet: no account has a password.

  A fresh installation stands here until its first admin follows the
  mailed link. While it does, every link this module mints goes into the
  server log as well, because an installation whose mail does not leave
  would otherwise be a house with the key locked inside.
  """
  def nobody_can_sign_in? do
    not Repo.exists?(from u in User, where: not is_nil(u.password_hash))
  end

  @doc "Whether this account is still waiting for its first password."
  def pending?(%User{password_hash: hash}), do: is_nil(hash)

  @doc """
  Invites an address: the account it gets, and the mailed link that
  gives the account a password. This is the one way in, whether the
  address came from Settings or from ADMIN_USERS.

  An address that is waiting for its first password gets a fresh link,
  which is what the Send-again button in Settings is. An address whose
  account has a password already answers `:exists`: nobody sets a
  password for a stranger by mailing themselves a link. The opts are
  the ones of `send_password_link/2`.

  A mail that cannot leave answers `{:mail, reason}` and leaves the
  account standing, so the link can go out again without making a
  second account.
  """
  def invite(email, opts) when is_binary(email) do
    case Repo.get_by(User, email: User.normalize_email(email)) do
      nil ->
        with {:ok, user} <- Repo.insert(User.invite_changeset(%User{}, %{email: email})) do
          remember_made(user.email)
          broadcast_users_changed()
          deliver_link(user, opts)
        end

      user ->
        if pending?(user), do: deliver_link(user, opts), else: {:error, :exists}
    end
  end

  @doc """
  What the start of the server does with ADMIN_USERS: an address in it
  that never had an account here gets one, and a link.

  An address this installation made an account for once is never made
  again here, because the accounts are the guest list and this variable
  only ever adds to it. An account somebody deleted stays deleted, an
  address whose owner moved to another one does not come back as a
  second account, and neither of them turns a restart into a way back
  in. What a deleted address needs to return is an invitation from
  Settings, by somebody who is in.

  While nobody can sign in, a restart mints the link of a waiting
  account again, because that restart is the only way back into an
  installation whose first mail never arrived. Once somebody has a
  password, a restart mails nobody.
  """
  def invite_configured(opts) do
    again? = nobody_can_sign_in?()
    made = made_here()

    Enum.each(admin_emails(), fn email ->
      email = User.normalize_email(email)

      case Repo.get_by(User, email: email) do
        nil ->
          unless email in made, do: report(email, invite(email, opts))

        user ->
          if again? and pending?(user) and not link_recently_sent?(user, opts),
            do: report(email, deliver_link(user, opts))
      end
    end)
  end

  # Every address this installation ever made an account for, whether
  # the configuration made it or an admin did. It outlives the accounts
  # it names, which is the whole point: the start of the server reads
  # it and adds nothing twice.
  defp made_here do
    :admin_emails_made |> Settings.get() |> String.split(",", trim: true)
  end

  defp remember_made(email) do
    made = made_here()

    unless email in made do
      {:ok, _} = Settings.put(:admin_emails_made, Enum.join(made ++ [email], ","))
    end

    :ok
  end

  # The start of the server has nobody to answer to, so what went wrong
  # goes into the log. The account it made stands either way, and
  # Settings sends its link again.
  defp report(_email, {:ok, _user}), do: :ok

  defp report(email, {:error, {:mail, reason}}) do
    Logger.error("""
    The account for #{email} is there, but its link did not leave this \
    server: #{inspect(reason)}

    Check the mail configuration, then send the link again from \
    Settings > Users.\
    """)
  end

  defp report(email, {:error, reason}) do
    Logger.error("ADMIN_USERS could not invite #{email}: #{inspect(reason)}")
  end

  defp deliver_link(user, opts) do
    with {:ok, _token} <- send_password_link(user, opts), do: {:ok, user}
  end

  ## Sign-in

  @doc """
  Finds the account of an address (any case) and verifies the password.
  Runs the hash either way, so an address without an account, and an
  account that is still waiting for its first password, take as long as
  a wrong password.
  """
  def authenticate_user(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: User.normalize_email(email))

    if User.valid_password?(user, password), do: {:ok, user}, else: :error
  end

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
  The user a live session token belongs to, or nil. A deleted account
  takes its sessions with it, so the browser it left open is out on its
  next request.
  """
  def get_user_by_session_token(token, opts \\ []) do
    hash = Session.hash(token)

    Repo.one(
      from s in Session,
        join: u in assoc(s, :user),
        where: s.token_hash == ^hash,
        where: s.expires_at > ^moment(opts),
        select: u
    )
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

  @doc "The account behind an email address (any case), or nil."
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: User.normalize_email(email))
  end

  @doc """
  Mails the user a link that sets a password: the invitation of a new
  admin and the password reset are the same link, and the mail says
  which of the two it is. The fresh link replaces any earlier one.
  `:link_url` turns the token into the URL for the mail; `:site` names
  the site in it. When the mail cannot leave, the answer says so instead
  of pretending.

  While nobody can sign in here, the link goes into the server log too.
  That is the way into an installation whose mail does not leave, and it
  closes itself: the first account that sets a password ends it.
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

    if nobody_can_sign_in?() do
      Logger.warning("""
      Nobody can sign in on this installation yet, so the link for \
      #{user.email} stands here as well:

          #{url}

      This line stops as soon as one account has a password.\
      """)
    end

    case UserNotifier.deliver_password_link(user, url, site) do
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

  # A link this old opens nothing. An invitation holds a week: it
  # travels to somebody who is not waiting for it, and a day is short
  # for a person who reads their mail on Monday. A reset holds a day,
  # because the person who asked for it is at the screen.
  @link_validity_in_hours 24
  @invitation_validity_in_hours 24 * 7

  @doc "How long a link for this account holds, in hours."
  def link_validity_in_hours(%User{} = user) do
    if pending?(user), do: @invitation_validity_in_hours, else: @link_validity_in_hours
  end

  @doc """
  The user a mailed link belongs to, while the link is fresh. Or
  `:error`.
  """
  def verify_login_link(token, opts \\ [])

  def verify_login_link(token, opts) when is_binary(token) do
    hash = LoginLink.hash(token)
    now = moment(opts)
    oldest = DateTime.add(now, -@invitation_validity_in_hours * 3600, :second)

    user =
      Repo.one(
        from l in LoginLink,
          join: u in assoc(l, :user),
          where: l.token_hash == ^hash,
          where: l.inserted_at > ^oldest,
          select: %{user: u, sent_at: l.inserted_at}
      )

    with %{user: user, sent_at: sent_at} <- user,
         true <- DateTime.diff(now, sent_at, :hour) < link_validity_in_hours(user) do
      {:ok, user}
    else
      _ -> :error
    end
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
  instead of raising. The address is free again afterwards, so the same
  person can be invited back.
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

  def update_display_name(user, display_name) do
    user
    |> User.display_name_changeset(%{display_name: display_name})
    |> Repo.update()
    |> tap_users_changed()
  end

  @doc """
  Moves the account to another address, against the current password.

  The address is the identity here, so this is the door to the whole
  account: whoever changes it owns every link that follows, the one
  that sets a new password included. A stolen session must not be
  enough to walk through it.

  A link that is still in flight to the old address dies with the move.
  Links belong to the account, not to the address, so one that was
  mailed a minute ago would otherwise still open the account from an
  inbox the owner just walked away from.
  """
  def update_email(user, email, current_password) do
    user = get_user!(user.id)
    changeset = User.email_changeset(user, %{email: email})

    if User.valid_password?(user, current_password) do
      changeset
      |> Repo.update()
      |> tap_link_spent()
      |> tap_users_changed()
    else
      {:error,
       changeset
       |> Ecto.Changeset.add_error(:current_password, "is not your current password")
       |> Map.put(:action, :update)}
    end
  end

  # A profile edit is also a users-list edit: the Settings screen of
  # every admin shows these fields.
  defp tap_link_spent({:ok, user} = result) do
    Repo.delete_all(from l in LoginLink, where: l.user_id == ^user.id)
    result
  end

  defp tap_link_spent(result), do: result

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

  @doc """
  The name others read: the displayed name, or the part of the address
  in front of the @ while it is blank. The address itself never reaches
  a reader, so the fallback stops there.
  """
  def display_name(user) do
    case user.display_name && String.trim(user.display_name) do
      nil -> local_part(user.email)
      "" -> local_part(user.email)
      name -> name
    end
  end

  defp local_part(email), do: email |> to_string() |> String.split("@") |> hd()

  # `now:` names the moment a deadline is judged at, so a test can
  # stand on the far side of a session or a link without back-dating
  # rows. Defaults to this moment.
  defp moment(opts) do
    opts
    |> Keyword.get_lazy(:now, fn -> DateTime.utc_now() end)
    |> DateTime.truncate(:second)
  end
end
