defmodule Texttile.Mailer.Lettermint do
  @moduledoc """
  Swoosh adapter for the Lettermint HTTP API.

  Swoosh's built-in `Swoosh.Adapters.Lettermint` drops `content_id` and
  `content_type` on attachments, which turns the newsletter preview
  square into a downloadable file beside a broken image. This adapter
  forwards both fields so inline `cid:` images render in mail clients.
  """

  use Swoosh.Adapter, required_config: [:api_token]

  alias Swoosh.Email

  @base_url "https://api.lettermint.co/v1"
  @api_endpoint "/send"

  def deliver(%Email{} = email, config \\ []) do
    headers = prepare_headers(config, email)
    body = email |> prepare_payload() |> Swoosh.json_library().encode!()
    url = [base_url(config), @api_endpoint]
    client = config[:api_client] || Swoosh.ApiClient

    case client.post(url, headers, body, email) do
      {:ok, code, _headers, body} when code in 200..299 ->
        case Swoosh.json_library().decode(body) do
          {:ok, response} when is_map(response) ->
            {:ok, %{id: Map.get(response, "message_id"), status: Map.get(response, "status")}}

          _ ->
            {:error, {code, body}}
        end

      {:ok, code, _headers, body} ->
        case Swoosh.json_library().decode(body) do
          {:ok, error} -> {:error, {code, error}}
          {:error, _} -> {:error, {code, body}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp base_url(config), do: config[:base_url] || @base_url

  defp prepare_headers(config, email) do
    headers = [
      {"Accept", "application/json"},
      {"Content-Type", "application/json"},
      {"x-lettermint-token", config[:api_token]}
    ]

    case email.provider_options do
      %{idempotency_key: key} when is_binary(key) and key != "" ->
        [{"Idempotency-Key", key} | headers]

      _ ->
        headers
    end
  end

  defp prepare_payload(email) do
    %{}
    |> put_from(email)
    |> put_to(email)
    |> put_list("cc", email.cc)
    |> put_list("bcc", email.bcc)
    |> put_reply_to(email.reply_to)
    |> put_present("subject", email.subject)
    |> put_present("text", email.text_body)
    |> put_present("html", email.html_body)
    |> put_headers(email.headers)
    |> put_metadata(email.provider_options)
    |> put_attachments(email.attachments)
  end

  defp put_from(payload, %{from: from}), do: Map.put(payload, "from", format_email(from))

  defp put_to(payload, %{to: to}), do: Map.put(payload, "to", Enum.map(to, &format_email/1))

  defp put_list(payload, _key, []), do: payload
  defp put_list(payload, key, list), do: Map.put(payload, key, Enum.map(list, &format_email/1))

  defp put_reply_to(payload, nil), do: payload
  defp put_reply_to(payload, []), do: payload

  defp put_reply_to(payload, list) when is_list(list) do
    Map.put(payload, "reply_to", Enum.map(list, &format_email/1))
  end

  defp put_reply_to(payload, reply_to) do
    Map.put(payload, "reply_to", [format_email(reply_to)])
  end

  defp put_present(payload, _key, nil), do: payload
  defp put_present(payload, _key, ""), do: payload
  defp put_present(payload, key, value), do: Map.put(payload, key, value)

  defp put_headers(payload, headers) when map_size(headers) == 0, do: payload
  defp put_headers(payload, headers), do: Map.put(payload, "headers", headers)

  defp put_metadata(payload, %{metadata: metadata}) when is_map(metadata) do
    Map.put(payload, "metadata", metadata)
  end

  defp put_metadata(payload, _), do: payload

  defp put_attachments(payload, []), do: payload

  defp put_attachments(payload, attachments) do
    Map.put(payload, "attachments", Enum.map(attachments, &prepare_attachment/1))
  end

  defp prepare_attachment(attachment) do
    data = %{
      "filename" => attachment.filename,
      "content" => Swoosh.Attachment.get_content(attachment, :base64)
    }

    data = put_present(data, "content_type", attachment.content_type)

    case {attachment.type, attachment.cid} do
      {:inline, cid} when is_binary(cid) and cid != "" ->
        Map.put(data, "content_id", cid)

      _ ->
        data
    end
  end

  defp format_email({name, email}) when name in [nil, ""], do: email
  defp format_email({name, email}), do: "#{name} <#{email}>"
  defp format_email(email) when is_binary(email), do: email
end
