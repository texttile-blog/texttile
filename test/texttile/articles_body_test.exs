defmodule Texttile.Articles.BodyTest do
  use Texttile.DataCase

  alias Texttile.Articles.Body
  alias Texttile.Articles.Body.Media

  # What every reference becomes, so a test reads the walk and not the
  # drawing: the caller decides what to draw, this says what it got.
  defp note(%Media{} = media) do
    kind = if media.video?, do: "film", else: "picture"
    "[#{kind} #{media.path} #{media.label}]"
  end

  defp walk(body), do: Body.to_html(body, &note/1)

  test "words without a reference come through as markdown" do
    assert walk("The **pier** at dawn.") =~ "<strong>pier</strong>"
  end

  test "a picture reference is handed over with its path and its label" do
    assert walk("![A pier](/uploads/images/pier.jpg)") =~ "[picture images/pier.jpg A pier]"
  end

  test "a reference to a film is marked as one" do
    assert walk("![Low tide](/uploads/videos/tide.mov)") =~ "[film videos/tide.mov Low tide]"
  end

  test "a reference without a label gets the word that stands in for one" do
    assert walk("![](/uploads/videos/tide.mov)") =~ "[film videos/tide.mov Video]"
  end

  test "every reference in the text is handed over, and nothing else is" do
    html =
      walk("![One](/uploads/a.jpg)\n\n![Two](/uploads/b.jpg)\n\n![Away](https://other/c.jpg)")

    assert html =~ "[picture a.jpg One]"
    assert html =~ "[picture b.jpg Two]"
    assert html =~ ~s(src="https://other/c.jpg")
  end

  # The exact strings assets/js/body_ed_core.js writes into the words,
  # copied here by hand. This is the whole contract between the editor
  # hook and the server: the hook writes them, the parser below reads
  # them, and nothing else states the shape.
  @uploading "![Uploading gull.jpg…]()"
  @failed "![Upload failed: fog.png]()"
  @done "![pier](/uploads/images/pier-abcd.jpg)"

  describe "refs/1" do
    test "reads finished uploads, running ones and failed ones from the words" do
      body = """
      Some prose.

      #{@done}

      #{@uploading}

      #{@failed}

      ![decorative]()
      """

      assert [
               %{kind: :done, file: "pier-abcd.jpg", url: "/uploads/images/pier-abcd.jpg"},
               %{kind: :running, file: "gull.jpg"},
               %{kind: :failed, file: "fog.png"}
             ] = Body.refs(body)
    end

    test "an empty body has no references" do
      assert Body.refs("") == []
      assert Body.refs(nil) == []
    end
  end

  describe "upload_paths/1" do
    test "answers the finished uploads, once each, without the /uploads/ in front" do
      body = "#{@done}\n\n#{@done}\n\n#{@uploading}\n\n![away](https://other/c.jpg)"

      assert Body.upload_paths(body) == ["images/pier-abcd.jpg"]
    end

    test "a body that uploaded nothing owns no file" do
      assert Body.upload_paths("Just words.") == []
    end
  end

  describe "rewrite/2" do
    test "hands every reference over and puts back what comes out" do
      rewritten = Body.rewrite(@done, fn _whole, alt, url -> "[#{alt}|#{url}]" end)

      assert rewritten == "[pier|/uploads/images/pier-abcd.jpg]"
    end
  end

  describe "picture/2" do
    test "keeps the tag the writer wrote and points it somewhere else" do
      drawn =
        Body.to_html("![A pier](/uploads/images/pier.jpg)", &Media.picture(&1, "/small.jpg"))

      assert drawn =~ ~s(src="/small.jpg")
      assert drawn =~ ~s(alt="A pier")
      refute drawn =~ "/uploads/images/pier.jpg"
    end
  end
end
