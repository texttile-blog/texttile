defmodule Texttile.VersionTest do
  use ExUnit.Case, async: true

  describe "version/0" do
    test "is the number that stands in mix.exs" do
      assert Texttile.version() == Mix.Project.config()[:version]
    end

    test "is three numbers, so a reader can compare two of them" do
      assert Texttile.version() =~ ~r/^\d+\.\d+\.\d+$/
    end
  end
end
