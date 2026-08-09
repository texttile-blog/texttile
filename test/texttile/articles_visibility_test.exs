defmodule Texttile.Articles.VisibilityTest do
  # Predicates over a struct, so no database and no sandbox.
  use ExUnit.Case, async: true

  alias Texttile.Articles.Article
  alias Texttile.Articles.Visibility

  defp entry(attrs), do: struct(%Article{status: "draft", type: "post"}, attrs)

  describe "live?/1" do
    test "a published entry is live" do
      assert Visibility.live?(entry(%{status: Visibility.live_status()}))
    end

    test "a draft, a scheduled entry and no entry at all are not" do
      refute Visibility.live?(entry(%{status: "draft"}))
      refute Visibility.live?(entry(%{status: "scheduled"}))
      refute Visibility.live?(nil)
    end
  end

  describe "open_for_comments?/1" do
    test "a live entry that allows comments takes one" do
      assert Visibility.open_for_comments?(entry(%{status: "published", allow_comments: true}))
    end

    test "an entry that is not live takes none, however its switch stands" do
      refute Visibility.open_for_comments?(entry(%{status: "draft", allow_comments: true}))
      refute Visibility.open_for_comments?(entry(%{status: "scheduled", allow_comments: true}))
    end

    test "a live entry with comments switched off takes none" do
      refute Visibility.open_for_comments?(entry(%{status: "published", allow_comments: false}))
    end
  end
end
