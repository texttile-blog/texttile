defmodule Texttile.ImportUploadTest do
  use ExUnit.Case, async: true

  alias Texttile.Import

  defp tmp_dir! do
    dir = Path.join(System.tmp_dir!(), "import-upload-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp source_file!(dir) do
    path = Path.join(dir, "export.zip")
    File.write!(path, "zip bytes")
    path
  end

  test "the uploaded zip is taken over, not copied" do
    source = source_file!(tmp_dir!())
    inode = File.stat!(source).inode

    kept = Import.keep_upload(source)
    on_exit(fn -> File.rm(kept) end)

    assert File.read!(kept) == "zip bytes"
    refute File.exists?(source)

    # The same file under a new name. A copy would answer a new inode,
    # and 1.6 GB of copying is what held the import page for a minute
    # and a half.
    assert File.stat!(kept).inode == inode
  end

  test "a zip that cannot be renamed still arrives" do
    dir = tmp_dir!()
    source = source_file!(dir)

    # Renaming asks for write permission on the folder, reading does
    # not. This is the stand-in for the source lying on another
    # filesystem, which renaming also refuses.
    File.chmod!(dir, 0o500)
    on_exit(fn -> File.chmod(dir, 0o700) end)

    kept = Import.keep_upload(source)
    on_exit(fn -> File.rm(kept) end)

    assert File.read!(kept) == "zip bytes"
  end
end
