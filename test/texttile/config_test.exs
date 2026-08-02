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

      assert Config.mailer_config(env) == [
               adapter: Swoosh.Adapters.SMTP,
               relay: "mail.example.com",
               port: 587,
               username: "u",
               password: "p",
               auth: :always,
               tls: :always
             ]
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
