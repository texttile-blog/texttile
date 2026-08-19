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

  describe "shared_root/1" do
    test "resolves to the main checkout, the one that owns the real .git directory" do
      # In a linked worktree .git is a file; only the main checkout has
      # the directory. This test passes from both.
      assert File.dir?(Path.join(Config.shared_root(), ".git"))
    end

    test "outside a git repository the directory is its own root" do
      tmp = System.tmp_dir!()
      assert Config.shared_root(tmp) == tmp
    end
  end

  describe "admin_emails/1" do
    test "reads the addresses from ADMIN_USERS" do
      assert Config.admin_emails(%{"ADMIN_USERS" => "kb@example.org,julia@example.org"}) ==
               ["kb@example.org", "julia@example.org"]
    end

    test "takes them as people write them: spaces, case, a trailing comma" do
      assert Config.admin_emails(%{"ADMIN_USERS" => " KB@Example.ORG , julia@example.org ,"}) ==
               ["kb@example.org", "julia@example.org"]
    end

    test "an unset or empty variable invites nobody" do
      assert Config.admin_emails(%{}) == []
      assert Config.admin_emails(%{"ADMIN_USERS" => "   "}) == []
    end

    # A username where an address belongs is the mistake this catches:
    # it could only ever be a leftover from the older setting.
    test "drops what is not an address" do
      assert Config.admin_emails(%{"ADMIN_USERS" => "kb,kb@example.org,not an address"}) ==
               ["kb@example.org"]
    end

    test "keeps every address once" do
      assert Config.admin_emails(%{"ADMIN_USERS" => "kb@example.org,KB@example.org"}) ==
               ["kb@example.org"]
    end
  end

  describe "mailer_config/1" do
    test "falls back to the local preview adapter when MAIL_ADAPTER is not set" do
      assert Config.mailer_config(%{}) == [adapter: Swoosh.Adapters.Local]
    end

    test "resend loads its API key" do
      assert Config.mailer_config(%{"MAIL_ADAPTER" => "resend", "RESEND_API_KEY" => "re_123"}) ==
               [adapter: Swoosh.Adapters.Resend, api_key: "re_123"]
    end

    test "postmark loads its API key" do
      assert Config.mailer_config(%{"MAIL_ADAPTER" => "postmark", "POSTMARK_API_KEY" => "pm"}) ==
               [adapter: Swoosh.Adapters.Postmark, api_key: "pm"]
    end

    test "brevo loads its API key" do
      assert Config.mailer_config(%{"MAIL_ADAPTER" => "brevo", "BREVO_API_KEY" => "bv"}) ==
               [adapter: Swoosh.Adapters.Brevo, api_key: "bv"]
    end

    test "ses loads region and AWS credentials" do
      env = %{
        "MAIL_ADAPTER" => "ses",
        "AWS_REGION" => "eu-central-1",
        "AWS_ACCESS_KEY_ID" => "AKIA",
        "AWS_SECRET_ACCESS_KEY" => "shhh"
      }

      assert Config.mailer_config(env) == [
               adapter: Swoosh.Adapters.AmazonSES,
               region: "eu-central-1",
               access_key: "AKIA",
               secret: "shhh"
             ]
    end

    test "smtp loads relay and credentials with STARTTLS defaults" do
      env = %{
        "MAIL_ADAPTER" => "smtp",
        "SMTP_HOST" => "mail.example.com",
        "SMTP_USERNAME" => "u",
        "SMTP_PASSWORD" => "p"
      }

      config = Config.mailer_config(env)

      assert config[:adapter] == Swoosh.Adapters.SMTP
      assert config[:relay] == "mail.example.com"
      assert config[:port] == 587
      assert config[:username] == "u"
      assert config[:password] == "p"
      assert config[:auth] == :always
      assert config[:tls] == :always
    end

    test "smtp verifies the relay's certificate against its name" do
      env = %{
        "MAIL_ADAPTER" => "smtp",
        "SMTP_HOST" => "mail.example.com",
        "SMTP_USERNAME" => "u",
        "SMTP_PASSWORD" => "p"
      }

      options = Config.mailer_config(env)[:tls_options]

      assert options[:verify] == :verify_peer
      assert options[:server_name_indication] == ~c"mail.example.com"
      assert is_list(options[:cacerts]) and options[:cacerts] != []
      assert options[:depth] == 3
      assert is_function(options[:customize_hostname_check][:match_fun], 2)
    end

    test "smtp port can be overridden" do
      env = %{
        "MAIL_ADAPTER" => "smtp",
        "SMTP_HOST" => "h",
        "SMTP_PORT" => "2525",
        "SMTP_USERNAME" => "u",
        "SMTP_PASSWORD" => "p"
      }

      assert Config.mailer_config(env)[:port] == 2525
    end

    test "a chosen adapter with a missing credential names the variable" do
      assert_raise RuntimeError, ~r/RESEND_API_KEY/, fn ->
        Config.mailer_config(%{"MAIL_ADAPTER" => "resend"})
      end
    end

    test "an unknown adapter names the valid options" do
      assert_raise RuntimeError, ~r/resend, postmark, brevo, smtp, ses/, fn ->
        Config.mailer_config(%{"MAIL_ADAPTER" => "sendgrid"})
      end
    end
  end

  describe "mail_from/1" do
    test "an explicit MAIL_FROM wins" do
      assert Config.mail_from(%{"MAIL_FROM" => "hello@breyer.blog"}) == "hello@breyer.blog"
    end

    test "falls back to texttile at the public host" do
      assert Config.mail_from(%{"PHX_HOST" => "demo.texttile.blog"}) ==
               "texttile@demo.texttile.blog"
    end

    test "falls back to localhost without a host" do
      assert Config.mail_from(%{}) == "texttile@localhost"
    end
  end

  describe "parse_dotenv/1" do
    test "parses KEY=VALUE lines" do
      assert Config.parse_dotenv("A=1\nB=two") == %{"A" => "1", "B" => "two"}
    end

    test "ignores comments, blank lines, and lines without =" do
      assert Config.parse_dotenv("# comment\n\nA=1\nnoise\n") == %{"A" => "1"}
    end

    test "keeps = inside values and strips optional quotes" do
      assert Config.parse_dotenv("A=x=y\nB=\"quoted\"\nC='single'") ==
               %{"A" => "x=y", "B" => "quoted", "C" => "single"}
    end

    test "accepts an export prefix" do
      assert Config.parse_dotenv("export A=1") == %{"A" => "1"}
    end
  end

  describe "dotenv/1" do
    test "returns an empty map when the file does not exist" do
      assert Config.dotenv("/nonexistent/.env") == %{}
    end

    @tag :tmp_dir
    test "reads and parses an existing file", %{tmp_dir: dir} do
      path = Path.join(dir, ".env")
      File.write!(path, "MAIL_ADAPTER=resend\n")
      assert Config.dotenv(path) == %{"MAIL_ADAPTER" => "resend"}
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
