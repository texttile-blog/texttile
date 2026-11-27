defmodule Texttile.Mailer.LettermintTest do
  use ExUnit.Case, async: true

  import Swoosh.Email

  alias Texttile.Mailer.Lettermint

  test "sends mail with token header, custom headers, and inline content_id" do
    test_pid = self()

    plug = fn conn ->
      {:ok, raw_body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:request, conn.method, conn.request_path, conn.req_headers, raw_body})

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(202, Jason.encode!(%{"message_id" => "msg_123", "status" => "pending"}))
    end

    email =
      new()
      |> from({"Texttile", "blog@texttile.blog"})
      |> to({"Reader", "reader@example.org"})
      |> subject("Harbor mornings")
      |> text_body("New entry")
      |> html_body(~s(<img src="cid:preview">))
      |> header("List-Unsubscribe", "<https://example.org/unsubscribe>")
      |> attachment(
        Swoosh.Attachment.new({:data, "jpeg-bytes"},
          filename: "preview.jpg",
          content_type: "image/jpeg",
          type: :inline,
          cid: "preview"
        )
      )
      |> attachment(
        Swoosh.Attachment.new({:data, "plain-bytes"},
          filename: "notes.txt",
          content_type: "text/plain"
        )
      )
      |> put_private(:client_options, plug: plug)

    assert {:ok, %{id: "msg_123", status: "pending"}} =
             Lettermint.deliver(email, api_token: "lm_secret", api_client: Swoosh.ApiClient.Req)

    assert_receive {:request, "POST", "/v1/send", headers, raw_body}
    assert {"x-lettermint-token", "lm_secret"} in headers

    payload = Jason.decode!(raw_body)
    assert payload["from"] == "Texttile <blog@texttile.blog>"
    assert payload["to"] == ["Reader <reader@example.org>"]
    assert payload["subject"] == "Harbor mornings"
    assert payload["text"] == "New entry"
    assert payload["html"] == ~s(<img src="cid:preview">)
    assert payload["headers"] == %{"List-Unsubscribe" => "<https://example.org/unsubscribe>"}

    # Swoosh.Email.attachment/2 prepends each attachment.
    assert payload["attachments"] == [
             %{
               "filename" => "notes.txt",
               "content" => Base.encode64("plain-bytes"),
               "content_type" => "text/plain"
             },
             %{
               "filename" => "preview.jpg",
               "content" => Base.encode64("jpeg-bytes"),
               "content_type" => "image/jpeg",
               "content_id" => "preview"
             }
           ]
  end

  test "returns decoded API errors on 4xx responses" do
    plug = fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(422, Jason.encode!(%{"error" => "Invalid sender"}))
    end

    email =
      new()
      |> from("blog@texttile.blog")
      |> to("reader@example.org")
      |> subject("Test")
      |> text_body("Hello")
      |> put_private(:client_options, plug: plug)

    assert {:error, {422, %{"error" => "Invalid sender"}}} =
             Lettermint.deliver(email, api_token: "lm_secret", api_client: Swoosh.ApiClient.Req)
  end
end
