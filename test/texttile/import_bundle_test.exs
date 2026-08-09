defmodule Texttile.Import.BundleTest do
  use ExUnit.Case, async: true

  alias Texttile.Import.Bundle

  @moduletag :tmp_dir

  # A tiny valid PNG, enough for a file that a picture check may read.
  @png Base.decode64!(
         "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
       )

  defp bundle(dir, front, body \\ "", files \\ []) do
    Enum.each(files, fn name ->
      path = Path.join(dir, name)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, @png)
    end)

    File.write!(Path.join(dir, "index.md"), "---\n#{front}---\n#{body}")
    Bundle.read(dir)
  end

  describe "a full bundle" do
    test "reads every field and keeps the gallery order", %{tmp_dir: dir} do
      bundle =
        bundle(
          dir,
          """
          title: Beach days
          slug: Beach-Days
          date: 2019-06-02
          status: draft
          type: page
          tags: [travel, sea]
          allow_comments: false
          preview: gallery/002.jpg
          gallery:
            - gallery/002.jpg
            - https://old.example/a.jpg
            - gallery/001.jpg
          """,
          "Hello ![map](map.png)\n",
          ["gallery/001.jpg", "gallery/002.jpg", "map.png"]
        )

      assert bundle.errors == []
      assert bundle.warnings == []
      assert bundle.title == "Beach days"
      assert bundle.slug == "beach-days"
      assert bundle.date == ~D[2019-06-02]
      assert bundle.status == "draft"
      assert bundle.type == "page"
      assert bundle.tags == ["travel", "sea"]
      assert bundle.allow_comments == false
      assert bundle.preview == "gallery/002.jpg"
      assert bundle.gallery == ["gallery/002.jpg", "https://old.example/a.jpg", "gallery/001.jpg"]
      assert bundle.body_refs == ["map.png"]
      assert bundle.body == "Hello ![map](map.png)\n"
    end

    test "fills the defaults", %{tmp_dir: dir} do
      bundle = bundle(dir, "title: Beach days\n")

      assert bundle.errors == []
      assert bundle.slug == "beach-days"
      assert bundle.date == nil
      assert bundle.status == "published"
      assert bundle.type == "post"
      assert bundle.tags == []
      assert bundle.allow_comments == true
      assert bundle.preview == nil
      assert bundle.gallery == []
    end
  end

  describe "the gallery shorthand" do
    test "without a gallery key the gallery folder counts, sorted by name", %{tmp_dir: dir} do
      bundle = bundle(dir, "title: A\n", "", ["gallery/b.jpg", "gallery/a.jpg"])
      assert bundle.gallery == ["gallery/a.jpg", "gallery/b.jpg"]
      assert bundle.warnings == []
    end

    test "an explicit key wins and unlisted files become a warning", %{tmp_dir: dir} do
      bundle =
        bundle(dir, "title: A\ngallery:\n  - gallery/a.jpg\n", "", [
          "gallery/a.jpg",
          "gallery/b.jpg"
        ])

      assert bundle.gallery == ["gallery/a.jpg"]
      assert [warning] = bundle.warnings
      assert warning =~ "gallery/b.jpg"
    end
  end

  describe "errors" do
    test "a missing index.md", %{tmp_dir: dir} do
      bundle = Bundle.read(dir)
      assert [error] = bundle.errors
      assert error =~ "index.md"
    end

    test "an unknown key", %{tmp_dir: dir} do
      assert [error] = bundle(dir, "title: A\ncolor: red\n").errors
      assert error =~ "color"
    end

    test "a missing title", %{tmp_dir: dir} do
      assert [error] = bundle(dir, "type: post\n").errors
      assert error =~ "title"
    end

    test "a title beyond 500 characters, which the article would refuse", %{tmp_dir: dir} do
      assert [error] = bundle(dir, "title: #{String.duplicate("x", 501)}\n").errors
      assert error =~ "500"
    end

    test "a list where a scalar belongs, and the other way round", %{tmp_dir: dir} do
      assert [error] = bundle(dir, "title: [a, b]\n").errors
      assert error =~ "title"

      assert [error] = bundle(dir, "title: A\ntags: blue\n").errors
      assert error =~ "tags"
    end

    test "a slug with nothing left after normalizing", %{tmp_dir: dir} do
      assert [error] = bundle(dir, "title: A\nslug: \"!!!\"\n").errors
      assert error =~ "slug"
    end

    test "a bad date, status, type, and allow_comments", %{tmp_dir: dir} do
      assert [error] = bundle(dir, "title: A\ndate: June 2nd\n").errors
      assert error =~ "date"

      assert [error] = bundle(dir, "title: A\nstatus: live\n").errors
      assert error =~ "status"

      assert [error] = bundle(dir, "title: A\ntype: article\n").errors
      assert error =~ "type"

      assert [error] = bundle(dir, "title: A\nallow_comments: yes\n").errors
      assert error =~ "allow_comments"
    end

    test "a relative source that is not in the bundle", %{tmp_dir: dir} do
      assert [error] = bundle(dir, "title: A\ngallery: [gone.jpg]\n").errors
      assert error =~ "gone.jpg"
    end

    test "a source that leaves the bundle folder", %{tmp_dir: dir} do
      assert [error] = bundle(dir, "title: A\ngallery: [../out.jpg]\n").errors
      assert error =~ ".."
    end

    test "a source that is not a supported picture", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "doc.pdf"), "pdf")
      assert [error] = bundle(dir, "title: A\n", "![doc](doc.pdf)\n").errors
      assert error =~ "doc.pdf"
    end

    test "a URL with an unsupported scheme", %{tmp_dir: dir} do
      assert [error] = bundle(dir, "title: A\ngallery: [ftp://old.example/a.jpg]\n").errors
      assert error =~ "ftp"
    end

    test "a preview that matches no source", %{tmp_dir: dir} do
      assert [error] =
               bundle(dir, "title: A\npreview: other.jpg\n", "", ["other.jpg", "gallery/a.jpg"]).errors

      assert error =~ "preview"
    end
  end

  describe "warnings" do
    test "a file that nothing references", %{tmp_dir: dir} do
      bundle = bundle(dir, "title: A\n", "", ["stray.jpg"])
      assert [warning] = bundle.warnings
      assert warning =~ "stray.jpg"
    end

    test "comments.yaml is read, not warned about", %{tmp_dir: dir} do
      File.write!(
        Path.join(dir, "comments.yaml"),
        "- author: kb\n  date: 2026-07-01 09:00\n  text: a\n"
      )

      bundle = bundle(dir, "title: A\n")
      assert bundle.warnings == []
      assert [%{author: "kb"}] = bundle.comments
    end
  end

  describe "the comments" do
    test "come with the bundle, in reading order", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "comments.yaml"), """
      - author: second
        date: 2026-07-02 09:00
        text: b
      - author: first
        date: 2026-07-01 09:00
        text: a
      """)

      bundle = bundle(dir, "title: A\n")
      assert bundle.errors == []
      assert Enum.map(bundle.comments, & &1.author) == ["first", "second"]
    end

    test "a broken file is an error of the bundle", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "comments.yaml"), "author: kb\n")

      bundle = bundle(dir, "title: A\n")
      assert [error] = bundle.errors
      assert error =~ "comments.yaml"
      assert bundle.comments == []
    end
  end

  describe "sources/1" do
    test "lists each source once, gallery first, body after, preview adds nothing", %{
      tmp_dir: dir
    } do
      bundle =
        bundle(
          dir,
          "title: A\npreview: shared.png\ngallery: [shared.png, https://old.example/a.jpg]\n",
          "![x](shared.png) ![y](inline.png)\n",
          ["shared.png", "inline.png"]
        )

      assert Bundle.sources(bundle) == ["shared.png", "https://old.example/a.jpg", "inline.png"]
    end
  end
end
