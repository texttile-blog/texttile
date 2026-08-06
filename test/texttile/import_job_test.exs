defmodule Texttile.Import.JobTest do
  use Texttile.DataCase, async: false

  import Texttile.AccountsFixtures

  alias Texttile.Articles.Article
  alias Texttile.Import.Job
  alias Texttile.Uploads

  setup do
    File.rm_rf!(Uploads.root())
    Job.subscribe()
    job = start_supervised!({Job, name: :import_job_under_test})
    %{job: job, user: user_fixture()}
  end

  defp zip_with_one_bundle! do
    source = Path.join(System.tmp_dir!(), "job-zip-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(source, "beach/gallery"))
    File.write!(Path.join(source, "beach/index.md"), "---\ntitle: Beach days\n---\nHello.\n")

    {:ok, black} = Vix.Vips.Operation.black(8, 4)
    :ok = Vix.Vips.Image.write_to_file(black, Path.join(source, "beach/gallery/a.jpg"))

    zip_path = Path.join(System.tmp_dir!(), "job-#{System.unique_integer([:positive])}.zip")

    {:ok, _} =
      :zip.create(String.to_charlist(zip_path), [~c"beach/index.md", ~c"beach/gallery/a.jpg"],
        cwd: String.to_charlist(source)
      )

    on_exit(fn ->
      File.rm_rf!(source)
      File.rm_rf!(zip_path)
    end)

    zip_path
  end

  test "the whole story: validate, report, run, done, discard", %{job: job, user: user} do
    assert Job.state(job).phase == :idle

    assert :ok = Job.validate(job, zip_with_one_bundle!(), "export.zip")
    assert_receive {:import_state, %{phase: :validating, name: "export.zip"}}, 2000
    assert_receive {:import_state, %{phase: :report, report: report}}, 2000
    assert [%{slug: "beach-days", errors: []}] = report.bundles

    assert :ok = Job.start_import(job, user)
    assert_receive {:import_state, %{phase: :running}}, 2000

    # the page hears what is being worked on, picture by picture
    assert_receive {:import_state, %{phase: :running, step: "picture 1 of 1:" <> _}}, 2000

    assert_receive {:import_state, %{phase: :done, summary: summary}}, 5000
    assert summary.created == 1
    assert Repo.get_by(Article, slug: "beach-days")

    assert :ok = Job.discard(job)
    assert Job.state(job).phase == :idle
  end

  test "a file that is no zip ends in the failed phase", %{job: job} do
    path = Path.join(System.tmp_dir!(), "no-zip-#{System.unique_integer([:positive])}")
    File.write!(path, "plain text")
    on_exit(fn -> File.rm_rf!(path) end)

    assert :ok = Job.validate(job, path, "no.zip")
    assert_receive {:import_state, %{phase: :failed, message: message}}, 2000
    assert message =~ "zip"

    assert :ok = Job.discard(job)
    assert Job.state(job).phase == :idle
  end

  test "the guards: nothing to import, and busy while running", %{job: job, user: user} do
    assert {:error, :not_ready} = Job.start_import(job, user)

    # a running import refuses everything except watching
    :sys.replace_state(job, fn state -> %{state | phase: :running} end)
    assert {:error, :busy} = Job.validate(job, "whatever.zip", "x.zip")
    assert {:error, :busy} = Job.discard(job)
    assert {:error, :not_ready} = Job.start_import(job, user)
    :sys.replace_state(job, fn state -> %{state | phase: :idle} end)
  end

  test "a second zip during the dry run is refused", %{job: job} do
    :sys.replace_state(job, fn state -> %{state | phase: :validating} end)
    assert {:error, :busy} = Job.validate(job, "whatever.zip", "x.zip")
    :sys.replace_state(job, fn state -> %{state | phase: :idle} end)
  end

  test "a crashed task turns into the failed phase", %{job: job} do
    ref = make_ref()
    task = %Task{ref: ref, pid: self(), owner: self(), mfa: {:erlang, :apply, 2}}
    :sys.replace_state(job, fn state -> %{state | phase: :running, task: task} end)

    send(job, {:DOWN, ref, :process, self(), :boom})
    assert_receive {:import_state, %{phase: :failed, message: message}}, 2000
    assert message =~ "crashed"

    assert :ok = Job.discard(job)
  end
end
