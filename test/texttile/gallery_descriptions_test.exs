defmodule Texttile.GalleryDescriptionsTest do
  use Texttile.DataCase, async: false

  import Texttile.ArticlesFixtures

  alias Texttile.{Articles, Gallery}

  setup do
    article = published_post(body: "The writer's **Markdown**.\n\n")
    file = jpg_fixture()
    on_exit(fn -> File.rm(file) end)
    {:ok, image} = Gallery.add_file(article, file, "IMG_0113.jpg")
    %{article: article, image: image}
  end

  test "descriptions change independently of the file, date, and body", %{
    article: article,
    image: image
  } do
    Phoenix.PubSub.subscribe(Texttile.PubSub, "article:#{article.id}")
    description = "A gull above the harbor."
    {:ok, updated} = Gallery.set_description(article.id, image.id, description, by: 42)

    assert updated.description == description
    assert updated.filename == image.filename
    assert updated.path == image.path
    assert updated.gallery_date == image.gallery_date
    assert Articles.get_article!(article.id).body == article.body
    assert_receive {:gallery_changed, _, %{action: :description, image_id: id, by: 42}}
    assert id == image.id
    assert [%{description: ^description}] = Gallery.tiles([updated])
  end

  test "a description can be cleared and survives delete and undo", %{
    article: article,
    image: image
  } do
    {:ok, _} = Gallery.set_description(article.id, image.id, "A gull.")
    {:ok, _} = Gallery.delete(article.id, image.id)
    assert {:error, :gone} = Gallery.set_description(article.id, image.id, "Too late")
    {:ok, restored} = Gallery.undo(article.id, image.id)
    assert restored.description == "A gull."
    {:ok, cleared} = Gallery.set_description(article.id, image.id, "")
    assert cleared.description == ""
  end

  test "a description belongs to this entry's tile only", %{image: image} do
    other = draft_post()
    assert {:error, :gone} = Gallery.set_description(other.id, image.id, "Wrong entry")
  end

  test "descriptions allow one line of at most 500 characters", %{article: article, image: image} do
    for value <- [String.duplicate("a", 501), "two\nlines", "two\rlines", %{}, nil] do
      assert {:error, :invalid_description} = Gallery.set_description(article.id, image.id, value)
    end

    value = String.duplicate("ü", 500)
    assert {:ok, %{description: ^value}} = Gallery.set_description(article.id, image.id, value)
  end
end
