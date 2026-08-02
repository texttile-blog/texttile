defmodule TexttileWeb.PageController do
  use TexttileWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
