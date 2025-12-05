defmodule CodeAgentEx.HfChat do
  @moduledoc """
  Simple HuggingFace Chat client for CodeAgent.
  """

  require Logger

  @base_url "https://router.huggingface.co"

  def chat_completion(model, messages, opts \\ []) do
    api_key = Keyword.get(opts, :api_key, System.get_env("HF_TOKEN"))

    if is_nil(api_key) or api_key == "" do
      {:error, "HF_TOKEN or :api_key required"}
    else
      url = "#{@base_url}/v1/chat/completions"

      # Payload de base avec les valeurs par défaut
      base_payload = %{
        model: model,
        messages: messages
      }

      # Merger les opts (tous les llm_opts sont passés au payload)
      payload = Map.merge(base_payload, Enum.into(opts, %{}))

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      Logger.debug("HF Chat API call to #{model}")

      case Req.post(url, json: payload, headers: headers, receive_timeout: 120_000) do
        {:ok, %{status: 200, body: body}} ->
          {:ok, body}

        {:ok, %{status: status, body: body}} ->
          Logger.error("HTTP #{status}: #{inspect(body)}")
          {:error, {:http_error, status, body}}

        {:error, reason} ->
          Logger.error("Request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
end
