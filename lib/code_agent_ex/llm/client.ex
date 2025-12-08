defmodule CodeAgentEx.LLM.Client do
  @moduledoc """
  Unified LLM client based on InstructorLite.

  This module replaces the previous OpenaiChat and HfChat modules,
  providing a single interface for structured LLM completions using
  InstructorLite's adapters.

  Supports any OpenAI-compatible API endpoint (OpenAI, HuggingFace Router,
  Grok, etc.) via the ChatCompletionsCompatible adapter.
  """

  require Logger
  alias CodeAgentEx.LLM.Schemas

  @doc """
  Performs a structured chat completion using InstructorLite.

  ## Arguments

  - `model` - Model name (e.g., "meta-llama/Llama-3-8b-chat-hf")
  - `messages` - List of message maps with :role and :content
  - `response_schema` - Ecto schema module for response structure (e.g., Schemas.CodeStep)
  - `opts` - Keyword list of options

  ## Options

  - `:api_key` - API key (defaults to HF_TOKEN or OPENAI_API_KEY env var)
  - `:base_url` - Base URL for the API (default: "https://router.huggingface.co/v1")
  - `:adapter` - InstructorLite adapter module (default: InstructorLite.Adapters.ChatCompletionsCompatible)
  - `:adapter_context` - Additional adapter context options (merged with default context)
  - `:receive_timeout` - Request timeout in ms (default: 120_000)
  - `:http_options` - Additional HTTP options
  - Any other InstructorLite options

  ## Returns

  - `{:ok, struct}` - Parsed response as the provided schema struct
  - `{:error, reason}` - Error details

  ## Examples

      iex> messages = [%{role: "user", content: "Calculate 10 + 5"}]
      iex> Client.chat_completion("gpt-4", messages, Schemas.CodeStep)
      {:ok, %Schemas.CodeStep{thought: "I need to add...", code: "result = 10 + 5"}}

      iex> Client.chat_completion("meta-llama/Llama-3-8b", messages, Schemas.TextResponse,
      ...>   base_url: "https://router.huggingface.co/v1",
      ...>   api_key: "hf_xxx")
      {:ok, %Schemas.TextResponse{answer: "15"}}
  """
  def chat_completion(model, messages, response_schema, opts \\ []) do
    # Extract configuration options
    api_key = Keyword.get(opts, :api_key) || System.get_env("HF_TOKEN") || System.get_env("OPENAI_API_KEY")
    base_url = Keyword.get(opts, :base_url, "https://router.huggingface.co/v1")
    adapter = Keyword.get(opts, :adapter, InstructorLite.Adapters.ChatCompletionsCompatible)
    receive_timeout = Keyword.get(opts, :receive_timeout, 120_000)

    if is_nil(api_key) or api_key == "" do
      {:error, "API key required (HF_TOKEN, OPENAI_API_KEY, or :api_key option)"}
    else
      Logger.debug("LLM Client: calling #{model} at #{base_url} with adapter #{inspect(adapter)} and schema #{inspect(response_schema)}")

      # Prepare params for InstructorLite
      params = %{
        model: model,
        messages: messages
      }

      # Build default adapter context
      default_context = [
        api_key: api_key,
        url: "#{base_url}/chat/completions",
        http_options: Keyword.get(opts, :http_options, [receive_timeout: receive_timeout])
      ]

      # Merge with custom adapter_context if provided
      adapter_context = Keyword.merge(default_context, Keyword.get(opts, :adapter_context, []))

      # Call InstructorLite with configurable adapter
      result =
        InstructorLite.instruct(
          params,
          response_model: response_schema,
          adapter: adapter,
          adapter_context: adapter_context
        )

      case result do
        {:ok, response} ->
          Logger.debug("LLM Client: success")
          {:ok, response}

        {:error, reason} ->
          Logger.error("LLM Client failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Convenience function for code generation steps.

  Uses the CodeStep schema by default.
  """
  def generate_code(model, messages, opts \\ []) do
    chat_completion(model, messages, Schemas.CodeStep, opts)
  end

  @doc """
  Convenience function for text responses.

  Uses the TextResponse schema by default.
  """
  def generate_text(model, messages, opts \\ []) do
    chat_completion(model, messages, Schemas.TextResponse, opts)
  end

  @doc """
  Convenience function for JSON responses.

  Uses the JsonResponse schema by default.
  Returns the data map directly instead of the struct.
  """
  def generate_json(model, messages, opts \\ []) do
    case chat_completion(model, messages, Schemas.JsonResponse, opts) do
      {:ok, %Schemas.JsonResponse{data: data}} -> {:ok, data}
      {:error, reason} -> {:error, reason}
    end
  end
end
