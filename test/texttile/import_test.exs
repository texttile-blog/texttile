defmodule Texttile.ImportTest do
  use Texttile.DataCase, async: false

  import Texttile.AccountsFixtures

  alias Texttile.Articles
  alias Texttile.Articles.Article
  alias Texttile.Gallery
  alias Texttile.Import
  alias Texttile.Uploads

  setup do
    Req.Test.stub(Texttile.ImportStub, fn conn -> respond_with_jpg(conn) end)
    %{user: user_fixture(), dir: tmp_dir!()}
  end

  # The subscriber mails leave in a task of their own, so the test
  # process has to be the one Swoosh delivers to.
  defp share_mail do
  end

  defp tmp_dir! do
    dir = Path.join(System.tmp_dir!(), "import-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp jpg!(path) do
    File.mkdir_p!(Path.dirname(path))
    {:ok, black} = Vix.Vips.Operation.black(8, 4)
    :ok = Vix.Vips.Image.write_to_file(black, path)
  end

  defp film!(path) do
    File.mkdir_p!(Path.dirname(path))
    File.cp!(Texttile.VideoFixtures.video_file(320, 240), path)
  end

  defp jpg_bytes! do
    path = Path.join(System.tmp_dir!(), "stub-#{System.unique_integer([:positive])}.jpg")
    jpg!(path)
    bytes = File.read!(path)
    File.rm!(path)
    bytes
  end

  defp respond_with_jpg(conn) do
    conn
    |> Plug.Conn.put_resp_content_type("image/jpeg")
    |> Plug.Conn.resp(200, if(conn.method == "HEAD", do: "", else: jpg_bytes!()))
  end

  defp write_bundle(dir, name, front, body \\ "", files \\ []) do
    bundle_dir = Path.join(dir, name)
    Enum.each(files, &jpg!(Path.join(bundle_dir, &1)))
    File.mkdir_p!(bundle_dir)
    File.write!(Path.join(bundle_dir, "index.md"), "---\n#{front}---\n#{body}")
    bundle_dir
  end

  describe "validate/1" do
    test "two bundles with the same slug are an error on both", %{dir: dir} do
      write_bundle(dir, "one", "title: Same\n")
      write_bundle(dir, "two", "title: Same\n")

      report = Import.validate(dir)

      assert [error_one] = Enum.find(report.bundles, &(&1.name == "one")).errors
      assert [error_two] = Enum.find(report.bundles, &(&1.name == "two")).errors
      assert error_one =~ "slug"
      assert error_two =~ "slug"
    end

    test "a slug that exists on the site becomes a warning", %{dir: dir, user: user} do
      {:ok, article} = Articles.create_draft(user)
      {:ok, _} = Articles.update_settings(article, %{slug: "beach-days"})

      write_bundle(dir, "beach", "title: Beach days\n")

      report = Import.validate(dir)
      assert [warning] = hd(report.bundles).warnings
      assert warning =~ "update"
    end

    test "a dead URL is an error, a live one is not, and hosts are listed", %{dir: dir} do
      Req.Test.stub(Texttile.ImportStub, fn conn ->
        case conn.host do
          "dead.example" -> Plug.Conn.resp(conn, 404, "")
          _ -> respond_with_jpg(conn)
        end
      end)

      write_bundle(
        dir,
        "beach",
        "title: A\ngallery: [https://live.example/a.jpg, https://dead.example/b.jpg]\n"
      )

      report = Import.validate(dir)
      assert [error] = hd(report.bundles).errors
      assert error =~ "dead.example/b.jpg"
      assert Enum.sort(report.hosts) == ["dead.example", "live.example"]
    end

    test "a URL that answers without a picture content type is an error", %{dir: dir} do
      Req.Test.stub(Texttile.ImportStub, fn conn ->
        conn |> Plug.Conn.put_resp_content_type("text/html") |> Plug.Conn.resp(200, "")
      end)

      write_bundle(dir, "beach", "title: A\ngallery: [https://old.example/gone]\n")

      report = Import.validate(dir)
      assert [error] = hd(report.bundles).errors
      assert error =~ "not a picture"
    end

    test "a host that refuses HEAD is asked again with a one byte GET", %{dir: dir} do
      Req.Test.stub(Texttile.ImportStub, fn conn ->
        case {conn.method, Plug.Conn.get_req_header(conn, "range")} do
          {"HEAD", _} ->
            Plug.Conn.resp(conn, 405, "")

          {"GET", ["bytes=0-0"]} ->
            conn
            |> Plug.Conn.put_resp_content_type("image/jpeg")
            |> Plug.Conn.put_resp_header("content-range", "bytes 0-0/1234")
            |> Plug.Conn.resp(206, "x")
        end
      end)

      write_bundle(dir, "beach", "title: A\ngallery: [https://shy.example/a.jpg]\n")
      assert hd(Import.validate(dir).bundles).errors == []
    end

    test "a redirecting URL is an error that names the target", %{dir: dir} do
      Req.Test.stub(Texttile.ImportStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "https://cdn.example/real.jpg")
        |> Plug.Conn.resp(301, "")
      end)

      write_bundle(dir, "beach", "title: A\ngallery: [https://old.example/a.jpg]\n")

      assert [error] = hd(Import.validate(dir).bundles).errors
      assert error =~ "redirects to https://cdn.example/real.jpg"
    end

    test "a URL into the private network is refused before any request", %{dir: dir} do
      Application.put_env(:texttile, :import_allow_private_hosts, false)
      on_exit(fn -> Application.put_env(:texttile, :import_allow_private_hosts, true) end)

      write_bundle(dir, "beach", "title: A\ngallery: [http://127.0.0.1/a.jpg]\n")

      assert [error] = hd(Import.validate(dir).bundles).errors
      assert error =~ "private network"
    end

    test "a picture whose declared size is beyond the cap is an error", %{dir: dir} do
      Application.put_env(:texttile, :import_max_picture_bytes, 1000)
      on_exit(fn -> Application.delete_env(:texttile, :import_max_picture_bytes) end)

      Req.Test.stub(Texttile.ImportStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("image/jpeg")
        |> Plug.Conn.put_resp_header("content-length", "5000")
        |> Plug.Conn.resp(200, "")
      end)

      write_bundle(dir, "beach", "title: A\ngallery: [https://old.example/big.jpg]\n")

      assert [error] = hd(Import.validate(dir).bundles).errors
      assert error =~ "cap"
    end

    test "an empty folder in the zip is a warning", %{dir: dir} do
      File.mkdir_p!(Path.join(dir, "hollow"))
      write_bundle(dir, "fine", "title: Fine\n")

      assert Enum.any?(Import.validate(dir).warnings, &(&1 =~ "hollow"))
    end

    test "a text open in an editor gets a warning", %{dir: dir, user: user} do
      {:ok, article} = Articles.create_draft(user)
      {:ok, _} = Articles.update_settings(article, %{slug: "beach-days"})
      me = self()
      :ok = Texttile.Articles.Lock.acquire(article.id, user.id, me)
      on_exit(fn -> Texttile.Articles.Lock.release(article.id, me) end)

      write_bundle(dir, "beach", "title: Beach days\n")

      warnings = hd(Import.validate(dir).bundles).warnings
      assert Enum.any?(warnings, &(&1 =~ "open in an editor"))
    end

    test "an address of another site in the words is a warning, not an error",
         %{dir: dir, user: user} do
      # This is what an export writes where the entry pointed at a
      # picture that had already gone. One error would skip the whole
      # bundle, and the entry would not be imported at all.
      write_bundle(dir, "beach", "title: Beach days\n", "Gone: ![map](/uploads/images/map.png)\n")

      report = Import.validate(dir)
      bundle = hd(report.bundles)

      assert bundle.errors == []
      assert Enum.any?(bundle.warnings, &(&1 =~ "/uploads/images/map.png"))
      assert Import.run(report, user).created == 1
      assert Repo.get_by!(Article, slug: "beach-days").body =~ "![map](/uploads/images/map.png)"
    end

    test "a gallery entry that appears twice is an error", %{dir: dir} do
      write_bundle(dir, "beach", "title: A\ngallery: [a.jpg, a.jpg]\n", "", ["a.jpg"])

      report = Import.validate(dir)
      assert [error] = hd(report.bundles).errors
      assert error =~ "twice"
    end
  end

  describe "films in a bundle" do
    test "a film beside the pictures becomes a tile and a film in the words",
         %{dir: dir, user: user} do
      bundle =
        write_bundle(
          dir,
          "harbour",
          "title: Harbour\ngallery:\n  - gallery/001_clip.mp4\n",
          "The walk ![walk](walk.mp4)\n"
        )

      film!(Path.join(bundle, "gallery/001_clip.mp4"))
      film!(Path.join(bundle, "walk.mp4"))

      report = Import.validate(dir)
      assert hd(report.bundles).errors == []
      assert Import.run(report, user).created == 1

      article = Repo.get_by!(Article, slug: "harbour")
      assert [tile] = Gallery.list(article.id)
      assert tile.filename == "001_clip.mp4"
      assert tile.path =~ ~r"^videos/"
      assert article.body =~ ~r"!\[walk\]\(/uploads/videos/[a-z0-9-]+\.mp4\)"
    end

    test "the gallery shorthand takes a film in gallery/ too", %{dir: dir, user: user} do
      bundle = write_bundle(dir, "harbour", "title: Harbour\n")
      film!(Path.join(bundle, "gallery/001_clip.mp4"))

      report = Import.validate(dir)
      assert hd(report.bundles).errors == []
      assert Import.run(report, user).created == 1

      assert [tile] =
               "harbour" |> then(&Repo.get_by!(Article, slug: &1)) |> then(&Gallery.list(&1.id))

      assert tile.filename == "001_clip.mp4"
    end

    test "a film behind a URL is refused, and the message says where films come from",
         %{dir: dir} do
      write_bundle(dir, "harbour", "title: Harbour\ngallery: [https://old.example/clip.mp4]\n")

      assert [error] = hd(Import.validate(dir).bundles).errors
      assert error =~ "film"
    end
  end

  describe "run/2" do
    test "imports a bundle completely", %{dir: dir, user: user} do
      write_bundle(
        dir,
        "beach",
        """
        title: Beach days
        date: 2019-06-02
        tags: [travel, sea]
        type: post
        allow_comments: false
        preview: gallery/bb.jpg
        gallery:
          - gallery/bb.jpg
          - gallery/aa.jpg
          - https://old.example/remote.jpg
        """,
        "The map ![map](map.png) and the first tile again ![bb](gallery/bb.jpg)\n",
        ["gallery/aa.jpg", "gallery/bb.jpg", "map.png"]
      )

      report = Import.validate(dir)
      assert Enum.all?(report.bundles, &(&1.errors == []))

      summary = Import.run(report, user)
      assert summary.created == 1
      assert summary.updated == 0
      assert summary.failed == []

      article = Repo.get_by!(Article, slug: "beach-days")
      assert article.title == "Beach days"
      assert article.status == "published"
      assert article.publish_date == ~D[2019-06-02]
      assert article.notified_on == ~D[2019-06-02]
      assert article.tags == "travel, sea"
      assert article.allow_comments == false

      # the tiles stand in list order, a second apart
      tiles = Gallery.list(article.id)
      assert Enum.map(tiles, & &1.filename) == ["bb.jpg", "aa.jpg", "remote.jpg"]
      assert Enum.map(tiles, & &1.gallery_date) == Enum.sort(Enum.map(tiles, & &1.gallery_date))

      # the body speaks in upload addresses now
      assert article.body =~ "](/uploads/images/map-"
      refute article.body =~ "](map.png)"

      # the shared source became one upload: the body reuses the tile's file
      [bb | _] = tiles
      assert article.body =~ "](/uploads/#{bb.path})"
      assert article.preview_path == bb.path

      # every file is on disk
      Enum.each([bb.path | Texttile.Articles.Body.upload_urls(article.body)], fn
        "/uploads/" <> relative -> assert File.regular?(Uploads.absolute(relative))
        relative -> assert File.regular?(Uploads.absolute(relative))
      end)

      assert Enum.any?(Articles.log(article), &(&1.text =~ "imported"))
    end

    test "an import tells the subscribers nothing", %{dir: dir, user: user} do
      share_mail()
      {:ok, _} = Texttile.Newsletter.add("reader@example.org")

      future = Date.utc_today() |> Date.add(30) |> Date.to_iso8601()
      write_bundle(dir, "beach", "title: Beach days\ndate: 2019-06-02\n")
      write_bundle(dir, "soon", "title: Soon\ndate: #{future}\n")

      Import.run(Import.validate(dir), user)

      refute_receive {:email, _}, 200

      # the scheduled one keeps its notification for its own day
      soon = Repo.get_by!(Article, slug: "soon")
      assert soon.status == "scheduled"
      assert is_nil(soon.notified_on)

      [gone_live] = Articles.go_live_due(soon.publish_date)
      assert gone_live.id == soon.id
      assert_receive {:email, %Swoosh.Email{subject: "New on Texttile: Soon"}}, 1000
    end

    test "a second import of a live text mails nobody either", %{dir: dir, user: user} do
      share_mail()
      {:ok, _} = Texttile.Newsletter.add("reader@example.org")

      write_bundle(dir, "beach", "title: Beach days\ndate: 2019-06-02\n")
      Import.run(Import.validate(dir), user)

      write_bundle(dir, "beach", "title: Beach days again\nslug: beach-days\ndate: 2019-06-02\n")
      Import.run(Import.validate(dir), user)

      assert Repo.get_by!(Article, slug: "beach-days").title == "Beach days again"
      refute_receive {:email, _}, 200
    end

    test "a future date schedules, a draft stays a draft", %{dir: dir, user: user} do
      future = Date.utc_today() |> Date.add(30) |> Date.to_iso8601()
      write_bundle(dir, "soon", "title: Soon\ndate: #{future}\n")
      write_bundle(dir, "quiet", "title: Quiet\nstatus: draft\ndate: 2020-01-01\n")

      Import.run(Import.validate(dir), user)

      assert Repo.get_by!(Article, slug: "soon").status == "scheduled"
      quiet = Repo.get_by!(Article, slug: "quiet")
      assert quiet.status == "draft"
      assert quiet.publish_date == ~D[2020-01-01]
    end

    test "the same zip twice updates instead of duplicating", %{dir: dir, user: user} do
      write_bundle(dir, "beach", "title: Beach days\ngallery: [a.jpg]\n", "![a](a.jpg)\n", [
        "a.jpg"
      ])

      Import.run(Import.validate(dir), user)
      first = Repo.get_by!(Article, slug: "beach-days")
      old_tile_paths = Gallery.paths(first.id)
      ["/uploads/" <> old_inline] = Texttile.Articles.Body.upload_urls(first.body)

      # the second bundle version drops the gallery and changes the text
      write_bundle(dir, "beach", "title: Beach days again\nslug: beach-days\n", "New body.\n")
      File.rm_rf!(Path.join(dir, "beach/gallery"))
      File.rm_rf!(Path.join(dir, "beach/a.jpg"))

      report = Import.validate(dir)
      summary = Import.run(report, user)
      assert summary.failed == []
      assert summary.updated == 1
      assert summary.created == 0

      again = Repo.get_by!(Article, slug: "beach-days")
      assert again.id == first.id
      assert again.title == "Beach days again"
      assert Gallery.list(again.id) == []

      # the pictures of the first import are gone, files included
      Enum.each(old_tile_paths, fn path ->
        refute File.regular?(Uploads.absolute(path))
      end)

      refute File.regular?(Uploads.absolute(old_inline))

      # the state before the update stays restorable as a version
      assert Enum.any?(Articles.versions(again), &(&1.title == "Beach days"))
    end

    test "a bundle with errors is skipped, the healthy one imports", %{dir: dir, user: user} do
      write_bundle(dir, "broken", "title: [not, a, scalar]\n")
      write_bundle(dir, "fine", "title: Fine\n")

      summary = Import.run(Import.validate(dir), user)
      assert summary.created == 1
      assert summary.skipped == 1
      assert Repo.get_by(Article, slug: "fine")
    end

    test "a URL that turns into json after the dry run fails only its bundle", %{
      dir: dir,
      user: user
    } do
      write_bundle(dir, "aaa", "title: A\ngallery: [https://old.example/a.jpg]\n")
      write_bundle(dir, "bbb", "title: B\n")

      report = Import.validate(dir)
      assert Enum.all?(report.bundles, &(&1.errors == []))

      # the host now answers the GET with a body Req would decode
      Req.Test.stub(Texttile.ImportStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"error":"gone"}))
      end)

      summary = Import.run(report, user)
      assert [{"aaa", message}] = summary.failed
      assert message =~ "a.jpg"
      assert summary.created == 1
      refute Repo.get_by(Article, slug: "a")
      assert Repo.get_by(Article, slug: "b")
    end

    test "a text open in an editor is refused at run time", %{dir: dir, user: user} do
      {:ok, article} = Articles.create_draft(user)
      {:ok, _} = Articles.update_settings(article, %{slug: "beach-days", tags: "keep"})
      me = self()
      :ok = Texttile.Articles.Lock.acquire(article.id, user.id, me)
      on_exit(fn -> Texttile.Articles.Lock.release(article.id, me) end)

      write_bundle(dir, "beach", "title: Beach days\n")

      summary = Import.run(Import.validate(dir), user)
      assert [{"beach", message}] = summary.failed
      assert message =~ "open in an editor"
      assert Repo.get_by!(Article, slug: "beach-days").tags == "keep"
    end

    test "a failure inside the transaction leaves no half-imported text", %{user: user} do
      # A title the dry run of an older release would have let through:
      # the article changeset refuses it, and the rollback must too.
      bundle = %Texttile.Import.Bundle{
        name: "long",
        dir: "/nowhere",
        title: String.duplicate("x", 501),
        slug: "long"
      }

      summary = Import.run(%Import.Report{bundles: [bundle]}, user)
      assert [{"long", _message}] = summary.failed
      assert Repo.aggregate(Article, :count) == 0
    end

    test "a body streaming past the cap fails its bundle", %{dir: dir, user: user} do
      Application.put_env(:texttile, :import_max_picture_bytes, 1000)
      on_exit(fn -> Application.delete_env(:texttile, :import_max_picture_bytes) end)

      write_bundle(dir, "beach", "title: A\ngallery: [https://old.example/liar.jpg]\n")

      # the HEAD stays silent about the size, the GET then streams past it
      Req.Test.stub(Texttile.ImportStub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("image/jpeg")
        |> Plug.Conn.resp(
          200,
          if(conn.method == "HEAD", do: "", else: String.duplicate("z", 5000))
        )
      end)

      report = Import.validate(dir)
      assert Enum.all?(report.bundles, &(&1.errors == []))

      summary = Import.run(report, user)
      assert [{"beach", message}] = summary.failed
      assert message =~ "cap"
      assert File.ls(Path.join(Uploads.root(), "images")) in [{:error, :enoent}, {:ok, []}]
    end

    test "a download that fails once and answers on the retry stays whole", %{
      dir: dir,
      user: user
    } do
      write_bundle(dir, "beach", "title: A\ngallery: [https://flaky.example/a.jpg]\n")
      report = Import.validate(dir)
      assert Enum.all?(report.bundles, &(&1.errors == []))

      base = Application.get_env(:texttile, :import_req_options)

      Application.put_env(
        :texttile,
        :import_req_options,
        base ++ [retry_delay: fn _attempt -> 1 end, retry_log_level: false]
      )

      on_exit(fn -> Application.put_env(:texttile, :import_req_options, base) end)

      # the first GET dies as a 502 error page, the retry has the bytes
      {:ok, attempts} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(Texttile.ImportStub, fn conn ->
        if conn.method == "GET" and Agent.get_and_update(attempts, &{&1, &1 + 1}) == 0 do
          conn
          |> Plug.Conn.put_resp_content_type("text/html")
          |> Plug.Conn.resp(502, "<html>bad gateway</html>")
        else
          respond_with_jpg(conn)
        end
      end)

      summary = Import.run(report, user)
      assert summary.failed == []

      # the stored file is the picture, whole and alone: a corrupt
      # concatenation would not read, let alone with these edges
      article = Repo.get_by!(Article, slug: "a")
      assert [%{width: 8, height: 4}] = Gallery.list(article.id)
    end

    test "the run narrates each picture and each retry", %{dir: dir, user: user} do
      write_bundle(dir, "beach", "title: A\ngallery: [https://flaky.example/a.jpg]\n")

      me = self()
      progress = fn event -> send(me, {:progress, event}) end

      report = Import.validate(dir, progress)
      assert_received {:progress, {:checking_url, "https://flaky.example/a.jpg", 1, 1}}

      base = Application.get_env(:texttile, :import_req_options)

      Application.put_env(
        :texttile,
        :import_req_options,
        base ++ [retry_delay: fn _attempt -> 1 end, retry_log_level: false]
      )

      on_exit(fn -> Application.put_env(:texttile, :import_req_options, base) end)

      {:ok, attempts} = Agent.start_link(fn -> 0 end)

      Req.Test.stub(Texttile.ImportStub, fn conn ->
        if conn.method == "GET" and Agent.get_and_update(attempts, &{&1, &1 + 1}) == 0 do
          Plug.Conn.resp(conn, 502, "bad gateway")
        else
          respond_with_jpg(conn)
        end
      end)

      summary = Import.run(report, user, progress)
      assert summary.failed == []

      assert_received {:progress, {:bundle, "beach", 1, 1}}
      assert_received {:progress, {:fetching, "https://flaky.example/a.jpg", 1, 1}}
      assert_received {:progress, {:retrying, "https://flaky.example/a.jpg", "answers 502"}}
    end

    test "replacing the gallery tells the open editors once", %{dir: dir, user: user} do
      write_bundle(dir, "beach", "title: Beach days\ngallery: [a.jpg]\n", "", ["a.jpg"])
      Import.run(Import.validate(dir), user)
      article = Repo.get_by!(Article, slug: "beach-days")

      # the second bundle version has no gallery at all
      write_bundle(dir, "beach", "title: Beach days\nslug: beach-days\n")
      File.rm_rf!(Path.join(dir, "beach/a.jpg"))

      Articles.subscribe(article.id)
      summary = Import.run(Import.validate(dir), user)
      assert summary.failed == []
      assert summary.updated == 1

      assert_receive {:gallery_changed, _id, %{action: :replaced}}
      assert Gallery.list(article.id) == []
    end

    test "a download that dies at run time leaves nothing behind", %{dir: dir, user: user} do
      write_bundle(dir, "beach", "title: A\ngallery: [https://old.example/a.jpg]\n")
      report = Import.validate(dir)
      assert Enum.all?(report.bundles, &(&1.errors == []))

      # the URL died between the dry run and the import
      Req.Test.stub(Texttile.ImportStub, fn conn -> Plug.Conn.resp(conn, 404, "") end)

      summary = Import.run(report, user)
      assert [{"beach", message}] = summary.failed
      assert message =~ "a.jpg"
      refute Repo.get_by(Article, slug: "a")
      assert File.ls(Path.join(Uploads.root(), "images")) in [{:error, :enoent}, {:ok, []}]
    end

    test "runs the bundles oldest first", %{dir: dir, user: user} do
      write_bundle(dir, "a-newest", "title: Newest\ndate: 2021-03-04\n")
      write_bundle(dir, "b-oldest", "title: Oldest\ndate: 2018-01-02\n")
      write_bundle(dir, "c-middle", "title: Middle\ndate: 2019-07-08\n")

      report = Import.validate(dir)
      assert Enum.map(report.bundles, & &1.name) == ["b-oldest", "c-middle", "a-newest"]

      me = self()

      summary =
        Import.run(report, user, fn
          {:bundle, name, _index, _total} -> send(me, {:bundle, name})
          _event -> :ok
        end)

      assert summary.created == 3
      assert_received {:bundle, first}
      assert_received {:bundle, second}
      assert_received {:bundle, third}
      assert [first, second, third] == ["b-oldest", "c-middle", "a-newest"]
    end
  end

  describe "the comments of a bundle" do
    defp write_comments(dir, name, yaml) do
      File.write!(Path.join([dir, name, "comments.yaml"]), yaml)
    end

    test "arrive under the entry, oldest first, replies behind them", %{dir: dir, user: user} do
      write_bundle(dir, "beach", "title: Beach days\ndate: 2019-06-02\n")

      write_comments(dir, "beach", """
      - author: Christiane
        email: christiane@example.org
        website: https://christiane.example
        date: 2019-06-03 22:14
        id: 12
        text: |
          Ihr Lieben, immer wieder!

          Es war ein Fest.
      - author: Jens
        date: 2019-06-05 08:00
        text: Schön war es.
      - author: kb
        date: 2019-06-04 09:02
        reply_to: 12
        text: Danke euch!
      """)

      summary = Import.run(Import.validate(dir), user)
      assert summary.failed == []

      article = Repo.get_by!(Article, slug: "beach-days")
      {comments, 0} = Texttile.Comments.for_readers(article.id)

      assert Enum.map(comments, & &1.name) == ["Christiane", "kb", "Jens"]
      assert hd(comments).body == "Ihr Lieben, immer wieder!\n\nEs war ein Fest."
      assert hd(comments).website == "https://christiane.example"
      assert DateTime.to_date(hd(comments).inserted_at) == ~D[2019-06-03]

      # readers meet them at once, whatever the confirmation setting says
      {:ok, _} = Texttile.Settings.put(:comments_require_confirmation, true)
      assert Enum.all?(comments, &Texttile.Comments.shown_to_readers?/1)
      assert Texttile.Comments.waiting_count() == 0
    end

    test "an import mails nobody about them", %{dir: dir, user: user} do
      share_mail()
      {:ok, _} = Texttile.Settings.put(:notify_on_comment, true)
      write_bundle(dir, "beach", "title: Beach days\n")
      write_comments(dir, "beach", "- author: kb\n  date: 2019-06-03 22:14\n  text: Schön.\n")

      assert Import.run(Import.validate(dir), user).failed == []
      refute_receive {:email, _}, 200
    end

    test "a broken comments.yaml keeps the whole bundle out", %{dir: dir, user: user} do
      write_bundle(dir, "beach", "title: Beach days\n")
      write_comments(dir, "beach", "- author: kb\n  text: no date here\n")

      report = Import.validate(dir)
      assert [error] = hd(report.bundles).errors
      assert error =~ "comments.yaml"

      summary = Import.run(report, user)
      assert summary.skipped == 1
      refute Repo.get_by(Article, slug: "beach-days")
    end

    test "the same zip twice leaves one set of comments", %{dir: dir, user: user} do
      write_bundle(dir, "beach", "title: Beach days\n")
      write_comments(dir, "beach", "- author: kb\n  date: 2019-06-03 22:14\n  text: Schön.\n")

      Import.run(Import.validate(dir), user)
      Import.run(Import.validate(dir), user)

      article = Repo.get_by!(Article, slug: "beach-days")
      assert Texttile.Comments.count_for(article.id) == 1
    end

    test "a bundle that closes its comments says so in the report", %{dir: dir} do
      write_bundle(dir, "beach", "title: Beach days\nallow_comments: false\n")
      write_comments(dir, "beach", "- author: kb\n  date: 2019-06-03 22:14\n  text: Schön.\n")

      assert [warning] = hd(Import.validate(dir).bundles).warnings
      assert warning =~ "readers see none of them"
    end

    test "a bundle without the file takes the comments of the earlier import away", %{
      dir: dir,
      user: user
    } do
      write_bundle(dir, "beach", "title: Beach days\n")
      write_comments(dir, "beach", "- author: kb\n  date: 2019-06-03 22:14\n  text: Schön.\n")
      Import.run(Import.validate(dir), user)

      File.rm!(Path.join([dir, "beach", "comments.yaml"]))
      summary = Import.run(Import.validate(dir), user)
      assert summary.updated == 1

      article = Repo.get_by!(Article, slug: "beach-days")
      assert Texttile.Comments.count_for(article.id) == 0
    end
  end

  describe "tmp_path/1" do
    # The zip extraction folders live in the same temp directory as the
    # picture downloads, and the name counter starts over with every
    # boot: a folder an earlier run left behind can carry the very name
    # a download draws next.
    test "clears a folder that stands on the name" do
      path = Path.join(System.tmp_dir!(), "texttile-fetch-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(path, "left-over"))
      on_exit(fn -> File.rm_rf(path) end)

      assert Import.tmp_path(path) == path
      assert {:ok, file} = File.open(path, [:write, :binary])
      File.close(file)
      assert File.regular?(path)
    end
  end

  describe "unpack/2" do
    test "unpacks bundles and warns about loose files at the root" do
      source = tmp_dir!()
      write_bundle(source, "beach", "title: A\n")
      File.write!(Path.join(source, "readme.txt"), "hello")
      zip = build_zip(source)

      dest = tmp_dir!()
      assert {:ok, warnings} = Import.unpack(zip, dest)
      assert File.regular?(Path.join(dest, "beach/index.md"))
      assert Enum.any?(warnings, &(&1 =~ "readme.txt"))
    end

    test "refuses an entry that climbs out of the archive", %{dir: dir} do
      zip_path = Path.join(dir, "evil.zip")

      {:ok, _} =
        :zip.create(String.to_charlist(zip_path), [{~c"../evil.txt", "boo"}])

      assert {:error, message} = Import.unpack(zip_path, tmp_dir!())
      assert message =~ "evil.txt"
    end

    test "refuses a zip beyond the entry cap", %{dir: dir} do
      Application.put_env(:texttile, :import_zip_limits, {2, 1_000_000})
      on_exit(fn -> Application.delete_env(:texttile, :import_zip_limits) end)

      source = tmp_dir!()
      write_bundle(source, "a", "title: A\n")
      write_bundle(source, "b", "title: B\n")
      write_bundle(source, "c", "title: C\n")

      assert {:error, message} = Import.unpack(build_zip(source), tmp_dir!())
      assert message =~ "entries"
      _ = dir
    end

    test "refuses a zip that unpacks beyond the size cap" do
      Application.put_env(:texttile, :import_zip_limits, {100, 500})
      on_exit(fn -> Application.delete_env(:texttile, :import_zip_limits) end)

      source = tmp_dir!()
      write_bundle(source, "a", "title: A\n", String.duplicate("padding ", 200))

      assert {:error, message} = Import.unpack(build_zip(source), tmp_dir!())
      assert message =~ "cap"
    end

    test "refuses what is not a zip", %{dir: dir} do
      path = Path.join(dir, "not.zip")
      File.write!(path, "plain text")
      assert {:error, _} = Import.unpack(path, tmp_dir!())
    end
  end

  defp build_zip(source) do
    zip_path = Path.join(tmp_dir!(), "export.zip")

    entries =
      source
      |> Path.join("**")
      |> Path.wildcard(match_dot: false)
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&String.to_charlist(Path.relative_to(&1, source)))

    {:ok, _} = :zip.create(String.to_charlist(zip_path), entries, cwd: String.to_charlist(source))
    zip_path
  end
end
