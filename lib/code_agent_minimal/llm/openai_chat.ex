defmodule CodeAgentMinimal.OpenaiChat do
  @moduledoc """
  OpenAI-compatible chat client for CodeAgent using openai_ex.

  Supports OpenAI, HuggingFace Router, and any OpenAI-compatible API.
  """

  require Logger

  @doc """
  Performs a chat completion using an OpenAI-compatible API.

  ## Options

  - `:api_key` - API key (defaults to HF_TOKEN or OPENAI_API_KEY env var)
  - `:base_url` - Base URL for the API (defaults to HuggingFace Router)
  - `:temperature` - Sampling temperature (default: 0.7)
  - `:max_tokens` - Maximum tokens to generate (default: 4000)
  - `:tool_choice` - Tool choice setting (default: "none")
  - Any other option supported by the API

  ## Examples

      iex> messages = [%{role: "user", content: "Hello!"}]
      iex> OpenaiChat.chat_completion("gpt-4", messages)
      {:ok, %{"choices" => [%{"message" => %{"content" => "Hi there!"}}]}}

      iex> OpenaiChat.chat_completion("meta-llama/Llama-3-8b-chat-hf", messages,
      ...>   base_url: "https://router.huggingface.co/v1",
      ...>   api_key: "hf_xxx")
  """
  def chat_completion(model, messages, opts \\ []) do
    # Extraire les options de configuration
    api_key = Keyword.get(opts, :api_key) || System.get_env("HF_TOKEN") || System.get_env("OPENAI_API_KEY")
    base_url = Keyword.get(opts, :base_url, "https://router.huggingface.co/v1")
    receive_timeout = Keyword.get(opts, :receive_timeout, 120_000)

    if is_nil(api_key) or api_key == "" do
      {:error, "API key required (HF_TOKEN, OPENAI_API_KEY, or :api_key option)"}
    else
      # Créer le client OpenaiEx avec URL personnalisée
      client =
        OpenaiEx.new(api_key)
        |> OpenaiEx.with_base_url(base_url)
        |> OpenaiEx.with_receive_timeout(receive_timeout)

      # Extraire les paramètres de completion (exclure les options de config)
      completion_params =
        opts
        |> Keyword.drop([:api_key, :base_url, :receive_timeout])
        |> Enum.into(%{})
        |> Map.put(:model, model)
        |> Map.put(:messages, messages)

      Logger.debug("OpenAI Chat API call to #{model} at #{base_url}")

      # Créer la requête de completion
      request = OpenaiEx.Chat.Completions.new(completion_params)

      # Exécuter la requête
      case OpenaiEx.Chat.Completions.create(client, request) do
        {:ok, response} when is_map(response) ->
          # openai_ex retourne directement la map décodée, pas une Finch.Response
          {:ok, response}

        {:error, reason} ->
          Logger.error("Request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
end
