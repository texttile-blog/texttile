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

  describe "visible?/2" do
    test "a reader sees what is live and nothing else" do
      assert Visibility.visible?(entry(%{status: "published"}), nil)
      refute Visibility.visible?(entry(%{status: "draft"}), nil)
      refute Visibility.visible?(entry(%{status: "scheduled"}), nil)
    end

    test "somebody signed in sees the entry whatever state it is in" do
      admin = %Texttile.Accounts.User{id: 1}

      assert Visibility.visible?(entry(%{status: "published"}), admin)
      assert Visibility.visible?(entry(%{status: "draft"}), admin)
      assert Visibility.visible?(entry(%{status: "scheduled"}), admin)
    end

    test "nothing is visible when there is no entry" do
      refute Visibility.visible?(nil, nil)
      refute Visibility.visible?(nil, %Texttile.Accounts.User{id: 1})
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
