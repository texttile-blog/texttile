defmodule TexttileWeb.UploadAnswer do
  @moduledoc """
  The answer both upload addresses give to a picture the entry already
  holds. It is said in one place, so the gallery and the text can never
  drift apart on it.

  409 and not 422: the file is fine, the entry is what refuses it.
  """
  use Gettext, backend: TexttileWeb.Gettext

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn, only: [put_status: 2]

  @doc "A 409 that names the picture this one already is."
  def duplicate(conn, name) do
    conn
    |> put_status(409)
    |> json(%{
      error: gettext("This picture is already in this entry, as %{name}.", name: name),
      of: name
    })
  end
end
