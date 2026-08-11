defmodule TexttileWeb.UploadNewsTest do
  use ExUnit.Case, async: true

  alias TexttileWeb.UploadNews

  describe "pcts/1" do
    test "turns the standing files into the progress display" do
      files = [
        %{"name" => "a.jpg", "status" => "uploading", "pct" => 40},
        %{"name" => "b.jpg", "status" => "failed", "pct" => 70}
      ]

      assert UploadNews.pcts(files) == %{"a.jpg" => 40, "b.jpg" => 70}
    end

    test "malformed state reads as nothing" do
      assert UploadNews.pcts(nil) == %{}
      assert UploadNews.pcts("x") == %{}
      assert UploadNews.pcts([%{"name" => 3, "pct" => "x"}, %{}]) == %{}
    end

    test "a client file name gets a short leash" do
      long = String.duplicate("a", 300) <> ".jpg"
      assert [{name, 1}] = Enum.to_list(UploadNews.pcts([%{"name" => long, "pct" => 1}]))
      assert String.length(name) == 120
    end
  end

  describe "read/1" do
    test "one inserted picture is named, a batch is counted" do
      assert %{log: "put gull.jpg into the text", needs_lock: true} =
               UploadNews.read(%{"kind" => "inserted", "names" => ["gull.jpg"]})

      assert %{log: "put 3 images into the text"} =
               UploadNews.read(%{"kind" => "inserted", "names" => ["a", "b", "c"]})
    end

    test "an arrival goes to the Log alone, a failure also to the state line" do
      assert %{log: "gull.jpg is in the text", note: nil} =
               UploadNews.read(%{"kind" => "done", "name" => "gull.jpg"})

      assert %{
               log: "gull.jpg failed to upload into the text",
               note: "gull.jpg failed at 40% · retry or remove it under the text"
             } = UploadNews.read(%{"kind" => "failed", "name" => "gull.jpg", "pct" => 40.4})
    end

    test "a refusal names the picture the entry already holds" do
      told = UploadNews.read(%{"kind" => "refused", "name" => "copy.jpg", "of" => "pier.jpg"})

      assert told.log == "copy.jpg is already in this entry, as pier.jpg"
      assert told.note =~ "already in this entry, as pier.jpg"
    end

    test "a removal tells cancel and cleanup apart" do
      assert %{log: "cancelled the upload of a.jpg"} =
               UploadNews.read(%{"kind" => "removed", "name" => "a.jpg", "how" => "cancel"})

      assert %{log: "took the marker for a.jpg out of the text"} =
               UploadNews.read(%{"kind" => "removed", "name" => "a.jpg", "how" => "remove"})
    end

    test "the browser's own answers need no lock" do
      too_big = UploadNews.read(%{"kind" => "too_big", "names" => ["big.mp4"], "roof" => 512})
      assert too_big.needs_lock == false
      assert too_big.note =~ "big.mp4 is over the 512 MB roof"

      missing = UploadNews.read(%{"kind" => "retry_missing", "name" => "a.jpg"})
      assert missing.needs_lock == false
      assert missing.note =~ "not in this browser any more"
    end

    test "a shape this module does not speak reads as nothing" do
      assert UploadNews.read(%{"kind" => "surprise"}) == nil
      assert UploadNews.read(%{"kind" => "failed", "name" => "a", "pct" => "NaN"}) == nil
      assert UploadNews.read("junk") == nil
    end
  end
end
