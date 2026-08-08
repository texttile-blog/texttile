defmodule TexttileWeb.AdminController do
  @moduledoc """
  The door of the admin area. `/admin` holds no screen of its own; it
  sends whoever signs in on to the entries, which is where the work
  starts and which has an address a bookmark can keep.
  """
  use TexttileWeb, :controller

  def index(conn, _params), do: redirect(conn, to: ~p"/admin/texts")
end
