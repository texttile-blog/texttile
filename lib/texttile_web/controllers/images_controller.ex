defmodule TexttileWeb.ImagesController do
  @moduledoc """
  Takes an image pasted or dropped into a text's body. The editor
  uploads the file here while the body holds an upload token in its
  place; the answer is the address the token becomes.
  """
  use TexttileWeb, :controller

  alias Texttile.Uploads

  def create(conn, %{"file" => %Plug.Upload{} = upload}) do
    case Uploads.put_body_image(upload.path, upload.filename) do
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
