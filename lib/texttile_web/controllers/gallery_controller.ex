defmodule TexttileWeb.GalleryController do
  @moduledoc """
  Takes a picture for a text's gallery. The editor shows the file as a
  local upload tile while it travels here; the answer names the image
  row every open editor is about to see appear.

  A picture this entry already holds is refused with a 409, and the
  answer names the picture it is.
  """
  use TexttileWeb, :controller

  alias Texttile.Articles
  alias Texttile.Gallery

  def create(conn, %{"id" => id, "file" => %Plug.Upload{} = upload}) do
    article = Articles.get_article!(id)
    user = conn.assigns.current_scope.user

    case Gallery.add_file(article, upload.path, upload.filename, by: user.id) do
      {:ok, image} ->
        json(conn, %{id: image.id})

      {:error, {:duplicate, name}} ->
        TexttileWeb.UploadAnswer.duplicate(conn, name)

      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: reason})
    end
  end

  def create(conn, _params) do
    conn |> put_status(400) |> json(%{error: "No file arrived"})
  end
end
