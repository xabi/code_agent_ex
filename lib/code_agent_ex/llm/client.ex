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

  @known_options [:api_key, :base_url, :adapter, :adapter_context, :receive_timeout, :http_options]

  @completion_schema NimbleOptions.new!(
    api_key: [
      type: :string,
      doc: "API key (defaults to HF_TOKEN or OPENAI_API_KEY env var)"
    ],
    base_url: [
      type: :string,
      default: "https://router.huggingface.co/v1",
      doc: "Base URL for the API"
    ],
    adapter: [
      type: :atom,
      default: InstructorLite.Adapters.ChatCompletionsCompatible,
      doc: "InstructorLite adapter module"
    ],
    adapter_context: [
      type: :keyword_list,
      default: [],
      doc: "Additional adapter context options (merged with default context)"
    ],
    receive_timeout: [
      type: :integer,
      default: 120_000,
      doc: "Request timeout in milliseconds"
    ],
    http_options: [
      type: :keyword_list,
      default: [],
      doc: "Additional HTTP options"
    ]
  )

  @doc """
  Performs a structured chat completion using InstructorLite.

  ## Arguments

  - `model` - Model name (e.g., "meta-llama/Llama-3-8b-chat-hf")
  - `messages` - List of message maps with :role and :content
  - `response_schema` - Ecto schema module for response structure (e.g., Schemas.CodeStep)
  - `opts` - Keyword list of options

  ## Options

  #{NimbleOptions.docs(@completion_schema)}

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
    # Split options: known ones to validate, unknown ones to pass through
    {known_opts, unknown_opts} = Keyword.split(opts, @known_options)

    validated_opts = NimbleOptions.validate!(known_opts, @completion_schema)

    # Extract configuration options
    api_key = validated_opts[:api_key] || System.get_env("HF_TOKEN") || System.get_env("OPENAI_API_KEY")
    base_url = validated_opts[:base_url]
    adapter = validated_opts[:adapter]
    receive_timeout = validated_opts[:receive_timeout]

    if is_nil(api_key) or api_key == "" do
      {:error, "API key required (HF_TOKEN, OPENAI_API_KEY, or :api_key option)"}
    else
      Logger.debug("LLM Client: calling #{model} at #{base_url} with adapter #{inspect(adapter)} and schema #{inspect(response_schema)}")

      # Prepare params for InstructorLite
      # Include base params + any additional API options (temperature, max_tokens, etc.)
      params =
        unknown_opts
        |> Enum.into(%{})
        |> Map.merge(%{
          model: model,
          messages: messages
        })

      # Build default adapter context
      http_options_with_timeout = Keyword.merge(
        validated_opts[:http_options],
        [receive_timeout: receive_timeout]
      )

      default_context = [
        api_key: api_key,
        url: "#{base_url}/chat/completions",
        http_options: http_options_with_timeout
      ]

      # Merge with custom adapter_context if provided
      adapter_context = Keyword.merge(default_context, validated_opts[:adapter_context])

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
