defmodule TexttileWeb.HumanCheckTest do
  use ExUnit.Case, async: true

  alias Texttile.Articles.Article
  alias TexttileWeb.HumanCheck

  @article %Article{id: 7}
  @now 1_700_000_000

  defp comment_params(age, extra \\ %{}) do
    stamp = HumanCheck.stamp({:comment, @article.id}, now: @now - age)
    Map.merge(%{"t" => stamp, "url" => ""}, extra)
  end

  defp newsletter_params(age, extra \\ %{}) do
    stamp = HumanCheck.stamp(:newsletter, now: @now - age)
    Map.merge(%{"t" => stamp, "url" => ""}, extra)
  end

  describe "the comment form" do
    test "a person's timing passes" do
      assert HumanCheck.human?({:comment, @article}, comment_params(10), now: @now)
    end

    test "a filled honeypot fails, whatever the timing says" do
      refute HumanCheck.human?({:comment, @article}, comment_params(10, %{"url" => "x"}),
               now: @now
             )
    end

    test "a form sent back within a script's seconds fails" do
      refute HumanCheck.human?({:comment, @article}, comment_params(0), now: @now)
      refute HumanCheck.human?({:comment, @article}, comment_params(2), now: @now)
      assert HumanCheck.human?({:comment, @article}, comment_params(3), now: @now)
    end

    test "no stamp, a broken stamp and a missing honeypot field all fail" do
      refute HumanCheck.human?({:comment, @article}, %{"url" => ""}, now: @now)
      refute HumanCheck.human?({:comment, @article}, %{"t" => "junk", "url" => ""}, now: @now)
      refute HumanCheck.human?({:comment, @article}, %{"t" => ["a"], "url" => %{}}, now: @now)
    end

    test "a stamp drawn for another entry fails" do
      foreign = HumanCheck.stamp({:comment, 8}, now: @now - 10)

      refute HumanCheck.human?({:comment, @article}, %{"t" => foreign, "url" => ""}, now: @now)
    end

    test "a stamp older than a week has expired" do
      refute HumanCheck.human?({:comment, @article}, comment_params(8 * 86_400), now: @now)
    end
  end

  describe "the newsletter form" do
    test "a person's timing passes, a script's fails" do
      assert HumanCheck.human?(:newsletter, newsletter_params(10), now: @now)
      refute HumanCheck.human?(:newsletter, newsletter_params(1), now: @now)
    end

    test "a filled honeypot fails" do
      refute HumanCheck.human?(:newsletter, newsletter_params(10, %{"url" => "spam"}), now: @now)
    end

    test "a comment stamp does not pass the newsletter form" do
      stamp = HumanCheck.stamp({:comment, @article.id}, now: @now - 10)

      refute HumanCheck.human?(:newsletter, %{"t" => stamp, "url" => ""}, now: @now)
    end
  end
end
