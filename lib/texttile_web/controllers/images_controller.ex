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
  alias TexttileWeb.UploadAnswer

  def create(conn, %{"id" => id, "file" => %Plug.Upload{} = upload}) do
    article = Articles.get_article!(id)

    if Videos.video?(upload.filename) do
      answer(conn, store_video(upload))
    else
      # Asking and storing stand together, so two pastes of one
      # photograph cannot both find nothing.
      case Articles.with_pictures_held(article, fn -> store_picture(article, upload) end) do
        {:duplicate, name} -> UploadAnswer.duplicate(conn, name)
        stored -> answer(conn, stored)
      end
    end
  end

  def create(conn, _params) do
    conn |> put_status(400) |> json(%{error: "No file arrived"})
  end

  defp store_picture(article, upload) do
    case Articles.duplicate_picture(article, upload.path) do
      nil -> Uploads.put_body_image(upload.path, upload.filename, article_id: article.id)
      name -> {:duplicate, name}
    end
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
end
