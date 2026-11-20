defmodule TexttileWeb.StatsComponentsTest do
  use ExUnit.Case, async: false

  alias TexttileWeb.StatsComponents

  # the thousands are grouped the way the blog's language writes them
  test "a count groups its thousands by the language of the blog" do
    Gettext.put_locale(TexttileWeb.Gettext, "en")
    assert StatsComponents.number(1017) == "1,017"
    assert StatsComponents.number(1_234_567) == "1,234,567"
    assert StatsComponents.number(999) == "999"

    Gettext.put_locale(TexttileWeb.Gettext, "de")
    assert StatsComponents.number(1017) == "1.017"
  after
    Gettext.put_locale(TexttileWeb.Gettext, "en")
  end
end
