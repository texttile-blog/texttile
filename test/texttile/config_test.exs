defmodule Texttile.ConfigTest do
  use ExUnit.Case, async: true

  alias Texttile.Config

  describe "database_path/1" do
    test "reads DATABASE_PATH from the environment" do
      assert Config.database_path(%{"DATABASE_PATH" => "/data/db/texttile.db"}) ==
               "/data/db/texttile.db"
    end

    test "raises with the variable name when DATABASE_PATH is missing" do
      assert_raise RuntimeError, ~r/DATABASE_PATH/, fn ->
        Config.database_path(%{})
      end
    end
  end

  describe "uploads_path/1" do
    test "reads UPLOADS_PATH from the environment" do
      assert Config.uploads_path(%{"UPLOADS_PATH" => "/data/uploads"}) == "/data/uploads"
    end

    test "raises with the variable name when UPLOADS_PATH is missing" do
      assert_raise RuntimeError, ~r/UPLOADS_PATH/, fn ->
        Config.uploads_path(%{})
      end
    end
  end
end
