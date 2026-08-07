defmodule TexttileWeb.ImagesController do
  @moduledoc """
  Takes a picture or a video pasted or dropped into a text's body. The
  editor uploads the file here while the body holds an upload token in
  its place; the answer is the address the token becomes.

  A video is stored and stands in line for its conversion at once. The
  answer names the original: that is the reference the body carries,
  and the page looks up what to play behind it.
  """
  use TexttileWeb, :controller

  alias Texttile.Uploads
  alias Texttile.Videos

  def create(conn, %{"file" => %Plug.Upload{} = upload}) do
    stored =
      if Videos.video?(upload.filename) do
        with {:ok, relative} <- Uploads.put_body_video(upload.path, upload.filename) do
          Videos.queue(relative)
          {:ok, relative}
        end
      else
        Uploads.put_body_image(upload.path, upload.filename)
      end

    case stored do
      {:ok, relative} ->
        json(conn, %{url: "/uploads/" <> relative})

      {:error, reason} ->
        conn |> put_status(422) |> json(%{error: reason})
    end
  end

  def create(conn, _params) do
    conn |> put_status(400) |> json(%{error: "No file arrived"})
  end
end
