defmodule Texttile.ArticlesFixtures do
  @moduledoc """
  Texts in every state the public site can meet: published posts and
  pages, drafts, scheduled texts. Built through the context, so every
  fixture went the way a real text goes.
  """

  import Texttile.AccountsFixtures

  alias Texttile.Articles

  @doc """
  A published blog post. `attrs` may carry `:title`, `:body`, `:tags`,
  `:slug`, `:type` and `:publish_date` (default today).
  """
  def published_post(attrs \\ %{}) do
    attrs = Map.new(attrs)
    {article, user} = draft(attrs)

    date = Map.get(attrs, :publish_date, Date.utc_today())
    {:ok, article} = Articles.set_publish_date(article, user, date)

    # `today:` never lies behind the date, so the fixture always comes
    # out published, past and future dates alike.
    {:ok, article} =
      Articles.publish(article, user, today: Enum.max([date, Date.utc_today()], Date))

    article
  end

  @doc "A published page: a post with `type: \"page\"`."
  def published_page(attrs \\ %{}) do
    attrs |> Map.new() |> Map.put(:type, "page") |> published_post()
  end

  @doc "A text scheduled for a future day."
  def scheduled_post(attrs \\ %{}) do
    attrs = Map.new(attrs)
    {article, user} = draft(attrs)

    date = Map.get(attrs, :publish_date, Date.add(Date.utc_today(), 7))
    {:ok, article} = Articles.set_publish_date(article, user, date)
    {:ok, article} = Articles.publish(article, user, today: Date.utc_today())
    article
  end

  @doc "A draft with text and settings, never published."
  def draft_post(attrs \\ %{}) do
    {article, _user} = draft(Map.new(attrs))
    article
  end

  defp draft(attrs) do
    user = Map.get_lazy(attrs, :user, fn -> user_fixture() end)
    {:ok, article} = Articles.create_draft(user)

    {:ok, article} =
      Articles.update_text(article, %{
        title: Map.get(attrs, :title, "A text"),
        body: Map.get(attrs, :body, "Plain words.")
      })

    settings = Map.take(attrs, [:type, :tags, :slug, :preview_path])

    {:ok, article} =
      if map_size(settings) == 0 do
        {:ok, article}
      else
        Articles.update_settings(article, settings)
      end

    {article, user}
  end

  @doc """
  A small real JPEG in a temp place, for gallery fixtures.

  Two black rectangles of one size are the same file byte for byte, and
  an entry takes each picture once. Every fixture is its own picture
  unless a test asks two of them to share a `mark:`.
  """
  def jpg_fixture(opts \\ []) do
    one = System.unique_integer([:positive])
    path = Path.join(System.tmp_dir!(), "public-#{one}.jpg")
    mark = Keyword.get(opts, :mark, "one-#{one}")
    {:ok, black} = Vix.Vips.Operation.black(20, 10)

    {:ok, image} =
      Vix.Vips.Image.mutate(black, fn mut ->
        Vix.Vips.MutableImage.set(mut, "exif-ifd0-ImageDescription", :gchararray, mark)
      end)

    :ok = Vix.Vips.Image.write_to_file(image, path)
    path
  end
end
