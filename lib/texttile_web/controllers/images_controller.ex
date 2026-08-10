defmodule TexttileWeb.ImagesController do
  @moduledoc """
  Takes a picture or a video pasted or dropped into a text's body. The
  editor uploads the file here while the body holds an upload token in
  its place; the answer is the address the token becomes.

  A video is stored and stands in line for its conversion at once. The
  answer names the original: that is the reference the body carries,
  and the page looks up what to play behind it.

  A picture this entry already holds is refused with a 409, and the
  answer names the picture it is. Films are taken as they come: a film
  is never read here.
  """
  use TexttileWeb, :controller

  alias Texttile.Articles
  alias Texttile.Uploads
  alias Texttile.Videos

  def create(conn, %{"id" => id, "file" => %Plug.Upload{} = upload}) do
    article = Articles.get_article!(id)

    cond do
      Videos.video?(upload.filename) ->
        answer(conn, store_video(upload))

      name = Articles.duplicate_picture(article, upload.path) ->
        refuse(conn, name)

      true ->
        answer(conn, Uploads.put_body_image(upload.path, upload.filename))
    end
  end

  def create(conn, _params) do
    conn |> put_status(400) |> json(%{error: "No file arrived"})
  end

  defp store_video(upload) do
    with {:ok, relative} <- Uploads.put_body_video(upload.path, upload.filename) do
      Videos.queue(relative)
      {:ok, relative}
    end
  end

  defp answer(conn, {:ok, relative}), do: json(conn, %{url: "/uploads/" <> relative})

  defp answer(conn, {:error, reason}),
    do: conn |> put_status(422) |> json(%{error: reason})

  defp refuse(conn, name) do
    conn
    |> put_status(409)
    |> json(%{
      error: gettext("This picture is already in this entry, as %{name}.", name: name),
      of: name
    })
  end
end
